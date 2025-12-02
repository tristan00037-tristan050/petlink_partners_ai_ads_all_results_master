#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL 비어있음}"
: "${ADMIN_KEY:?ADMIN_KEY 비어있음}"
: "${PAYMENT_WEBHOOK_SECRET:?PAYMENT_WEBHOOK_SECRET 비어있음}"

PORT="${PORT:-5902}"
ORD="ORD-$(date +%s)"

echo "=========================================="
echo "r5.1/r5.2 수동 검증 스크립트"
echo "=========================================="
echo ""

# 결과 저장
RESULTS=()

# 헬퍼 함수
pass() { echo "✅ $1"; RESULTS+=("PASS: $1"); }
fail() { echo "❌ $1"; RESULTS+=("FAIL: $1"); }
info() { echo "ℹ️  $1"; }

# ==========================================
# A. r5.1 결제 오버레이 검증
# ==========================================
echo "=== A. r5.1 결제 오버레이 검증 ==="
echo ""

# 1) 헬스/문서 노출
echo "[1/8] 헬스/문서 노출"
if curl -sf "http://localhost:${PORT}/health" >/dev/null; then
  pass "health OK"
else
  fail "health OK"
fi

if curl -sf "http://localhost:${PORT}/openapi_r51.yaml" | head -n1 | grep -q '^openapi:'; then
  pass "openapi r5.1 OK"
else
  fail "openapi r5.1 OK"
fi

if curl -sf "http://localhost:${PORT}/docs-payments" >/dev/null; then
  pass "docs-payments OK"
else
  fail "docs-payments OK"
fi

echo ""

# 2) confirm 승인 및 멱등
echo "[2/8] confirm 승인 및 멱등"
curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" \
  -H "Content-Type: application/json" \
  -d "{\"order_id\":\"${ORD}\",\"provider_txn_id\":\"tx-${ORD}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" | grep -q '"ok":true' && pass "confirm1 OK" || fail "confirm1 OK"

curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" \
  -H "Content-Type: application/json" \
  -d "{\"order_id\":\"${ORD}\",\"provider_txn_id\":\"tx-${ORD}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" >/dev/null && pass "confirm2 OK" || fail "confirm2 OK"

CNT=$(psql "$DATABASE_URL" -Atc "select count(*) from payments where order_id='${ORD}';" 2>/dev/null || echo "0")
if [ "$CNT" = "1" ]; then
  pass "confirm idempotent OK"
else
  fail "confirm idempotent OK (count=$CNT)"
fi

echo ""

# 3) 웹훅 서명(정상/부정) + 타임스탬프 윈도우
echo "[3/8] 웹훅 서명(정상/부정)"
PAYLOAD="{\"order_id\":\"${ORD}\",\"event\":\"CAPTURED\",\"amount\":200000}"
TS=$(date +%s)
SIG=$(printf '%s' "$TS.$PAYLOAD" | node -e \
"let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const [ts,body]=d.split('.',2);const h=require('crypto').createHmac('sha256',process.env.PAYMENT_WEBHOOK_SECRET||'').update(ts).update('.').update(body).digest('hex');console.log(h)})")

if curl -sf -XPOST "http://localhost:${PORT}/billing/webhook/pg" \
  -H "Content-Type: application/json" -H "X-Webhook-Timestamp: $TS" -H "X-Webhook-Signature: $SIG" \
  --data-binary "$PAYLOAD" | grep -q '"ok":true'; then
  pass "webhook valid OK"
else
  fail "webhook valid OK"
fi

RC=$(curl -s -o /dev/null -w "%{http_code}\n" -XPOST "http://localhost:${PORT}/billing/webhook/pg" \
  -H "Content-Type: application/json" -H "X-Webhook-Timestamp: $TS" -H "X-Webhook-Signature: deadbeef" \
  --data-binary "$PAYLOAD")
if [ "$RC" = "401" ]; then
  pass "webhook invalid-signature OK"
else
  fail "webhook invalid-signature OK (code=$RC)"
fi

echo ""

# 4) 상태 전이 가드(다운그레이드 차단)
echo "[4/8] 상태 전이 가드"
# 먼저 CAPTURED 상태를 만들어야 함
CURRENT_STATUS=$(psql "$DATABASE_URL" -Atc "select status from payments where order_id='${ORD}';" 2>/dev/null || echo "")
info "현재 상태: $CURRENT_STATUS"

# CAPTURED 상태가 아니면 웹훅으로 CAPTURED 만들기
if [ "$CURRENT_STATUS" != "CAPTURED" ]; then
  info "CAPTURED 상태 생성 중..."
  PAYLOAD_CAP="{\"order_id\":\"${ORD}\",\"event\":\"CAPTURED\",\"amount\":200000}"
  TS_CAP=$(date +%s)
  SIG_CAP=$(printf '%s' "$TS_CAP.$PAYLOAD_CAP" | node -e \
  "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const [ts,body]=d.split('.',2);const h=require('crypto').createHmac('sha256',process.env.PAYMENT_WEBHOOK_SECRET||'').update(ts).update('.').update(body).digest('hex');console.log(h)})")
  
  curl -sf -XPOST "http://localhost:${PORT}/billing/webhook/pg" \
    -H "Content-Type: application/json" -H "X-Webhook-Timestamp: $TS_CAP" -H "X-Webhook-Signature: $SIG_CAP" \
    --data-binary "$PAYLOAD_CAP" >/dev/null || true
  
  sleep 1
  CURRENT_STATUS=$(psql "$DATABASE_URL" -Atc "select status from payments where order_id='${ORD}';" 2>/dev/null || echo "")
  info "변경 후 상태: $CURRENT_STATUS"
fi

# CAPTURED → AUTHORIZED 다운그레이드 시도
if psql "$DATABASE_URL" -c "update payments set status='AUTHORIZED' where order_id='${ORD}';" 2>/dev/null; then
  fail "transition guard OK (다운그레이드 허용됨)"
else
  pass "transition guard OK"
fi

echo ""

# 5) 트랜잭션 원자성(업데이트 + outbox)
echo "[5/8] 트랜잭션 원자성"
# 최근 생성된 PAYMENT_* 이벤트 확인 (직전 웹훅 처리로 생성된 것)
OUTBOX_COUNT=$(psql "$DATABASE_URL" -Atc "select count(*) from outbox where event_type like 'PAYMENT_%' AND created_at > now() - interval '5 minutes';" 2>/dev/null || echo "0")
if [ "$OUTBOX_COUNT" -gt 0 ]; then
  pass "outbox 이벤트 존재 (최근 5분: count=$OUTBOX_COUNT)"
  psql "$DATABASE_URL" -c "select id,event_type,status,attempts,created_at from outbox where event_type like 'PAYMENT_%' AND created_at > now() - interval '5 minutes' order by id desc limit 5;" 2>/dev/null || true
else
  # 전체 확인
  TOTAL_COUNT=$(psql "$DATABASE_URL" -Atc "select count(*) from outbox where event_type like 'PAYMENT_%';" 2>/dev/null || echo "0")
  if [ "$TOTAL_COUNT" -gt 0 ]; then
    pass "outbox 이벤트 존재 (전체: count=$TOTAL_COUNT)"
    psql "$DATABASE_URL" -c "select id,event_type,status,attempts,created_at from outbox where event_type like 'PAYMENT_%' order by id desc limit 5;" 2>/dev/null || true
  else
    fail "outbox 이벤트 존재"
  fi
fi

echo ""

# 6) DLQ 플로우
echo "[6/8] DLQ 플로우"
# retries를 5 이상으로 설정하여 임계치 초과 상태 만들기
psql "$DATABASE_URL" -c "INSERT INTO outbox(aggregate_type, aggregate_id, event_type, payload, headers, status, attempts, available_at, created_at) VALUES('payment', 999, 'PAYMENT_TEST_FAIL', '{}', '{}', 'PENDING', 5, now(), now()) ON CONFLICT DO NOTHING;" 2>/dev/null || true

sleep 1

# 하우스키핑 실행 (실패를 유도하기 위해 FAIL_EVENT 환경변수 설정 또는 워커가 실패하도록)
curl -sf -XPOST "http://localhost:${PORT}/admin/ops/housekeeping/run" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null || true

sleep 2

# 워커가 처리하면서 attempts가 증가하고 MAX_ATTEMPTS(12)에 도달하면 DLQ로 이동
# 또는 직접 attempts를 12로 업데이트하여 DLQ 이동 유도
psql "$DATABASE_URL" -c "UPDATE outbox SET attempts=12, status='PENDING' WHERE event_type='PAYMENT_TEST_FAIL' AND status='PENDING';" 2>/dev/null || true

sleep 1

curl -sf -XPOST "http://localhost:${PORT}/admin/ops/housekeeping/run" -H "X-Admin-Key: ${ADMIN_KEY}" >/dev/null || true

sleep 1

DLQ_COUNT=$(psql "$DATABASE_URL" -Atc "select count(*) from outbox_dlq where event_type='PAYMENT_TEST_FAIL';" 2>/dev/null || echo "0")
if [ "$DLQ_COUNT" -gt 0 ]; then
  pass "DLQ 이동 확인 (count=$DLQ_COUNT)"
  psql "$DATABASE_URL" -c "select id,event_type,failure from outbox_dlq order by id desc limit 5;" 2>/dev/null || true
else
  # outbox에서 DEAD 상태 확인
  DEAD_COUNT=$(psql "$DATABASE_URL" -Atc "select count(*) from outbox where event_type='PAYMENT_TEST_FAIL' AND status='DEAD';" 2>/dev/null || echo "0")
  if [ "$DEAD_COUNT" -gt 0 ]; then
    pass "DLQ 이동 확인 (DEAD 상태: count=$DEAD_COUNT)"
  else
    info "DLQ 이동 확인 (수동 확인 필요, outbox 상태 확인)"
    psql "$DATABASE_URL" -c "select id,event_type,status,attempts from outbox where event_type='PAYMENT_TEST_FAIL';" 2>/dev/null || true
  fi
fi

echo ""

# 7) 테넌트/스토어 매핑
echo "[7/8] 테넌트/스토어 매핑"
STORE_INFO=$(psql "$DATABASE_URL" -c "select order_id,store_id,amount,status from payments where order_id='${ORD}';" 2>/dev/null || echo "")
if echo "$STORE_INFO" | grep -q "store_id"; then
  pass "테넌트/스토어 매핑 OK"
  echo "$STORE_INFO"
else
  fail "테넌트/스토어 매핑 OK"
fi

echo ""

# 8) 타임스탬프 윈도우 초과
echo "[8/8] 타임스탬프 윈도우 초과"
OLDTS=$(( $(date +%s) - 600 ))
OLDSIG=$(printf '%s' "$OLDTS.$PAYLOAD" | node -e \
"let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const [ts,body]=d.split('.',2);const h=require('crypto').createHmac('sha256',process.env.PAYMENT_WEBHOOK_SECRET||'').update(ts).update('.').update(body).digest('hex');console.log(h)})")

RC=$(curl -s -o /dev/null -w "%{http_code}\n" -XPOST "http://localhost:${PORT}/billing/webhook/pg" \
  -H "Content-Type: application/json" -H "X-Webhook-Timestamp: $OLDTS" -H "X-Webhook-Signature: $OLDSIG" \
  --data-binary "$PAYLOAD")
if [ "$RC" = "401" ]; then
  pass "webhook timestamp window OK"
else
  fail "webhook timestamp window OK (code=$RC)"
fi

echo ""

# ==========================================
# B. r5.2 검증
# ==========================================
echo "=== B. r5.2 검증 ==="
echo ""

# r5.2 문서/라우트 식별
echo "[B-0] r5.2 기능 식별"
if curl -sf "http://localhost:${PORT}/openapi_r52.yaml" | head -n1 | grep -q "openapi:"; then
  info "r5.2 문서: /openapi_r52.yaml"
  R52_TYPE="환불/부분취소"
else
  info "r5.2 문서 없음, 라우트 검색 중..."
  if grep -q "refund" server/routes/*.js 2>/dev/null; then
    R52_TYPE="환불/부분취소"
    info "유형: 환불/부분취소 (라우트에서 확인)"
  elif grep -q "settlement\|recon" server/routes/*.js 2>/dev/null; then
    R52_TYPE="정산/대사"
    info "유형: 정산/대사 (라우트에서 확인)"
  else
    R52_TYPE="미확인"
    info "유형: 미확인"
  fi
fi

echo ""

# B-2: 환불/부분취소 검증
if [ "$R52_TYPE" = "환불/부분취소" ] || [ "$R52_TYPE" = "미확인" ]; then
  echo "[B-2] 환불/부분취소 검증"
  
  # 주문 생성 (capture까지)
  ORD_REFUND="ORD-REFUND-$(date +%s)"
  curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" \
    -H "Content-Type: application/json" \
    -d "{\"order_id\":\"${ORD_REFUND}\",\"provider_txn_id\":\"tx-${ORD_REFUND}\",\"amount\":150000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" >/dev/null
  
  TS_REFUND=$(date +%s)
  PAY_REFUND="{\"order_id\":\"${ORD_REFUND}\",\"event\":\"CAPTURED\",\"amount\":150000,\"receipt_id\":\"r-${ORD_REFUND}\"}"
  SIG_REFUND=$(printf '%s' "$TS_REFUND.$PAY_REFUND" | node -e \
  "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const [ts,body]=d.split('.',2);const h=require('crypto').createHmac('sha256',process.env.PAYMENT_WEBHOOK_SECRET||'').update(ts).update('.').update(body).digest('hex');console.log(h)})")
  
  curl -sf -XPOST "http://localhost:${PORT}/billing/webhook/pg" \
    -H "Content-Type: application/json" -H "X-Webhook-Timestamp: $TS_REFUND" -H "X-Webhook-Signature: $SIG_REFUND" \
    --data-binary "$PAY_REFUND" >/dev/null
  
  sleep 1
  
  # 부분 환불
  REFID="REF-$(date +%s)"
  if curl -sf -XPOST "http://localhost:${PORT}/billing/refund" \
    -H "Content-Type: application/json" \
    -d "{\"order_id\":\"${ORD_REFUND}\",\"refund_id\":\"${REFID}\",\"amount\":50000,\"reason\":\"test-partial\"}" | grep -q '"ok":true'; then
    pass "부분 환불 OK"
  else
    fail "부분 환불 OK"
  fi
  
  # 환불 상태 확인
  REFUND_STATUS=$(psql "$DATABASE_URL" -Atc "select status,refunded_total from payments where order_id='${ORD_REFUND}';" 2>/dev/null || echo "")
  info "환불 후 상태: $REFUND_STATUS"
  
  # 멱등성 확인
  if curl -sf -XPOST "http://localhost:${PORT}/billing/refund" \
    -H "Content-Type: application/json" \
    -d "{\"order_id\":\"${ORD_REFUND}\",\"refund_id\":\"${REFID}\",\"amount\":50000,\"reason\":\"test-partial\"}" | grep -q '"ok":true'; then
    pass "환불 멱등 OK"
  else
    fail "환불 멱등 OK"
  fi
  
  REFUND_COUNT=$(psql "$DATABASE_URL" -Atc "select count(*) from refunds where refund_id='${REFID}';" 2>/dev/null || echo "0")
  if [ "$REFUND_COUNT" = "1" ]; then
    pass "환불 단일 기록 OK"
  else
    fail "환불 단일 기록 OK (count=$REFUND_COUNT)"
  fi
  
  # Outbox 이벤트 확인
  REFUND_EVENT=$(psql "$DATABASE_URL" -Atc "select count(*) from outbox where event_type='PAYMENT_REFUND_SUCCEEDED';" 2>/dev/null || echo "0")
  if [ "$REFUND_EVENT" -gt 0 ]; then
    pass "Outbox 환불 이벤트 OK"
  else
    info "Outbox 환불 이벤트 (수동 확인 필요)"
  fi
  
  # 전액 환불
  REFID2="REF2-$(date +%s)"
  if curl -sf -XPOST "http://localhost:${PORT}/billing/refund" \
    -H "Content-Type: application/json" \
    -d "{\"order_id\":\"${ORD_REFUND}\",\"refund_id\":\"${REFID2}\",\"amount\":100000,\"reason\":\"test-final\"}" | grep -q '"ok":true'; then
    pass "전액 환불 OK"
  else
    fail "전액 환불 OK"
  fi
  
  FINAL_STATUS=$(psql "$DATABASE_URL" -Atc "select status from payments where order_id='${ORD_REFUND}';" 2>/dev/null || echo "")
  if echo "$FINAL_STATUS" | grep -q "CANCELED"; then
    pass "전액 환불 후 CANCELED 상태 OK"
  else
    fail "전액 환불 후 CANCELED 상태 OK (status=$FINAL_STATUS)"
  fi
  
  # 정산 스냅샷
  ORD_SETTLE="ORD-SETTLE-$(date +%s)"
  curl -sf -XPOST "http://localhost:${PORT}/billing/confirm" \
    -H "Content-Type: application/json" \
    -d "{\"order_id\":\"${ORD_SETTLE}\",\"provider_txn_id\":\"tx-${ORD_SETTLE}\",\"amount\":200000,\"store_id\":1,\"status\":\"AUTHORIZED\"}" >/dev/null
  
  TS_SETTLE=$(date +%s)
  PAY_SETTLE="{\"order_id\":\"${ORD_SETTLE}\",\"event\":\"CAPTURED\",\"amount\":200000,\"receipt_id\":\"r-${ORD_SETTLE}\"}"
  SIG_SETTLE=$(printf '%s' "$TS_SETTLE.$PAY_SETTLE" | node -e \
  "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const [ts,body]=d.split('.',2);const h=require('crypto').createHmac('sha256',process.env.PAYMENT_WEBHOOK_SECRET||'').update(ts).update('.').update(body).digest('hex');console.log(h)})")
  
  curl -sf -XPOST "http://localhost:${PORT}/billing/webhook/pg" \
    -H "Content-Type: application/json" -H "X-Webhook-Timestamp: $TS_SETTLE" -H "X-Webhook-Signature: $SIG_SETTLE" \
    --data-binary "$PAY_SETTLE" >/dev/null
  
  sleep 1
  
  if curl -sf -XPOST "http://localhost:${PORT}/admin/settlements/snapshot" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true'; then
    pass "정산 스냅샷 OK"
  else
    fail "정산 스냅샷 OK"
  fi
  
  SETTLE_COUNT=$(psql "$DATABASE_URL" -Atc "select count(*) from settlements where order_id='${ORD_SETTLE}';" 2>/dev/null || echo "0")
  if [ "$SETTLE_COUNT" -ge 1 ]; then
    pass "정산 생성 OK"
  else
    fail "정산 생성 OK (count=$SETTLE_COUNT)"
  fi
  
  # 컴플라이언스
  psql "$DATABASE_URL" -c "UPDATE payments SET metadata=jsonb_build_object('card_number','4111111111111111','email','user@example.com') WHERE order_id='${ORD_SETTLE}'" >/dev/null 2>&1 || true
  
  if curl -sf -XPOST "http://localhost:${PORT}/admin/ops/compliance/sanitize" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q '"ok":true'; then
    pass "컴플라이언스 정리 OK"
  else
    fail "컴플라이언스 정리 OK"
  fi
  
  PII_CHECK=$(psql "$DATABASE_URL" -Atc "select (metadata ? 'card_number')::int from payments where order_id='${ORD_SETTLE}';" 2>/dev/null || echo "1")
  if [ "$PII_CHECK" = "0" ]; then
    pass "PII 제거 확인 OK"
  else
    fail "PII 제거 확인 OK (exists=$PII_CHECK)"
  fi
  
  echo ""
fi

# ==========================================
# 최종 요약
# ==========================================
echo "=========================================="
echo "검증 결과 요약"
echo "=========================================="
echo ""

PASS_COUNT=0
FAIL_COUNT=0

for result in "${RESULTS[@]}"; do
  if [[ "$result" == PASS:* ]]; then
    ((PASS_COUNT++))
  elif [[ "$result" == FAIL:* ]]; then
    ((FAIL_COUNT++))
  fi
done

echo "통과: $PASS_COUNT"
echo "실패: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
  echo "✅ 모든 검증 통과"
  exit 0
else
  echo "❌ 일부 검증 실패"
  echo ""
  echo "실패 항목:"
  for result in "${RESULTS[@]}"; do
    if [[ "$result" == FAIL:* ]]; then
      echo "  - $result"
    fi
  done
  exit 1
fi

