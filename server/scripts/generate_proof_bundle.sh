#!/usr/bin/env bash
# generate_proof_bundle.sh - 증빙 번들 생성 스크립트

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:5902}"
ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"

OUT="proof_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

echo "=== 증빙 번들 생성 시작 ==="
echo "출력 디렉토리: $OUT"
echo ""

# 1) 가입/토큰
echo "1. 가입/토큰 발급..."
TOK_RESP=$(curl -s -XPOST "${BASE_URL}/auth/signup")
TOK=$(echo "$TOK_RESP" | jq -r '.token // empty' || echo "")
if [ -z "$TOK" ] || [ "$TOK" = "null" ]; then
    echo "   ❌ 토큰 발급 실패"
    echo "$TOK_RESP" > "$OUT/error_token.txt"
    exit 1
fi
echo "$TOK" > "$OUT/token.txt"
echo "$TOK_RESP" | jq . > "$OUT/signup.json"
STORE_ID=$(echo "$TOK_RESP" | jq -r '.store_id // 1')
echo "   ✅ 토큰 발급 성공 (store_id: ${STORE_ID})"
echo ""

# 2) 페이싱 적용(오늘)
echo "2. 페이싱 적용..."
TODAY=$(date +"%Y-%m-%d")
TODAY_MONTH=$(date +"%Y-%m")
pacer_apply_resp=$(curl -s -XPOST "${BASE_URL}/pacer/apply" \
    -H "Authorization: Bearer ${TOK}" \
    -H "X-Store-ID: ${STORE_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"store_id\":${STORE_ID},\"month\":\"${TODAY_MONTH}\",\"schedule\":[{\"date\":\"${TODAY}\",\"amount\":1000,\"min\":800,\"max\":1200}]}")
echo "$pacer_apply_resp" | jq . > "$OUT/pacer_apply.json"
if echo "$pacer_apply_resp" | grep -q '"ok":true'; then
    echo "   ✅ Pacer 적용 성공"
else
    echo "   ⚠️ Pacer 적용 실패 (계속 진행)"
fi
echo ""

# 3) 초안 → 발행 → 승인토큰 → 승인
echo "3. 초안 생성 및 발행..."
draft_create_resp=$(curl -s -XPOST "${BASE_URL}/organic/drafts" \
    -H "Authorization: Bearer ${TOK}" \
    -H "X-Store-ID: ${STORE_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"store_id\":${STORE_ID},\"copy\":\"상담/방문 안내\",\"channels\":[\"META\",\"YOUTUBE\"]}")
echo "$draft_create_resp" | jq . > "$OUT/draft_create.json"
DRAFT_ID=$(echo "$draft_create_resp" | jq -r '.draft_id // 1')
echo "   ✅ 초안 생성 성공 (draft_id: ${DRAFT_ID})"

echo "   초안 발행..."
draft_publish_resp=$(curl -s -XPOST "${BASE_URL}/organic/drafts/${DRAFT_ID}/publish" \
    -H "Authorization: Bearer ${TOK}" \
    -H "X-Store-ID: ${STORE_ID}")
echo "$draft_publish_resp" | jq . > "$OUT/draft_publish.json"
if echo "$draft_publish_resp" | grep -q '"ok":true'; then
    echo "   ✅ 초안 발행 성공"
    
    # 승인 토큰 추출
    APPROVE=$(echo "$draft_publish_resp" | jq -r '.draft.results[]? | select(.approve_token != null) | .approve_token' | head -n1)
    if [ -n "$APPROVE" ] && [ "$APPROVE" != "null" ] && [ "$APPROVE" != "" ]; then
        echo "   승인 토큰으로 승인..."
        draft_approve_resp=$(curl -s -XPOST "${BASE_URL}/organic/drafts/${DRAFT_ID}/approve" \
            -H "Authorization: Bearer ${TOK}" \
            -H "X-Store-ID: ${STORE_ID}" \
            -H "Content-Type: application/json" \
            -d "{\"token\":\"${APPROVE}\"}")
        echo "$draft_approve_resp" | jq . > "$OUT/draft_approve.json"
        if echo "$draft_approve_resp" | grep -q '"ok":true'; then
            echo "   ✅ 승인 성공"
        else
            echo "   ⚠️ 승인 실패 (계속 진행)"
        fi
    else
        echo "   ⚠️ 승인 토큰 없음 (계속 진행)"
    fi
else
    echo "   ⚠️ 초안 발행 실패 (계속 진행)"
fi
echo ""

# 4) 인게스트 → 상한 도달 → 발행 차단 증빙
echo "4. 인게스트 및 상한 도달 테스트..."
ingest_resp=$(curl -s -XPOST "${BASE_URL}/ingest/META" \
    -H "Authorization: Bearer ${TOK}" \
    -H "X-Store-ID: ${STORE_ID}" \
    -H "Content-Type: application/json" \
    -d "[{\"ts\":\"$(date -u +%FT%TZ)\",\"store_id\":${STORE_ID},\"cost\":1300}]")
echo "$ingest_resp" | jq . > "$OUT/ingest.json"
if echo "$ingest_resp" | grep -q '"ok":true'; then
    echo "   ✅ 인게스트 성공"
    
    echo "   상한 초과 시 발행 차단 확인..."
    publish_after_cap_resp=$(curl -s -XPOST "${BASE_URL}/organic/drafts/${DRAFT_ID}/publish" \
        -H "Authorization: Bearer ${TOK}" \
        -H "X-Store-ID: ${STORE_ID}")
    echo "$publish_after_cap_resp" | jq . > "$OUT/publish_after_cap.json"
    if echo "$publish_after_cap_resp" | grep -q '"error":"DAILY_CAP_REACHED"'; then
        echo "   ✅ 일일 상한 초과 차단 확인"
    else
        echo "   ⚠️ 일일 상한 초과 차단 미확인 (계속 진행)"
    fi
else
    echo "   ⚠️ 인게스트 실패 (계속 진행)"
fi
echo ""

# 5) 메트릭/엔진 상태
echo "5. 메트릭 및 엔진 상태 조회..."
engine_today_resp=$(curl -s -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: ${STORE_ID}" "${BASE_URL}/engine/today")
echo "$engine_today_resp" | jq . > "$OUT/engine_today.json"
if echo "$engine_today_resp" | grep -q '"ok":true'; then
    echo "   ✅ Engine Today 조회 성공"
else
    echo "   ⚠️ Engine Today 조회 실패 (계속 진행)"
fi

metrics_resp=$(curl -s "${BASE_URL}/metrics")
echo "$metrics_resp" | jq . > "$OUT/metrics.json"
if echo "$metrics_resp" | grep -q '"ok":true'; then
    echo "   ✅ Metrics 조회 성공"
else
    echo "   ⚠️ Metrics 조회 실패 (계속 진행)"
fi
echo ""

# 6) 감사 로그(API; r2에 /admin/audit 존재 시)
if [ -n "${ADMIN_KEY:-}" ]; then
    echo "6. 감사 로그 조회..."
    admin_audit_resp=$(curl -s -H "X-Admin-Key: ${ADMIN_KEY}" "${BASE_URL}/admin/audit?limit=200" || echo '{"ok":false,"error":"NOT_IMPLEMENTED"}')
    echo "$admin_audit_resp" | jq . > "$OUT/admin_audit.json"
    if echo "$admin_audit_resp" | grep -q '"ok":true'; then
        echo "   ✅ 감사 로그 조회 성공"
    else
        echo "   ⚠️ 감사 로그 조회 실패 (미구현 가능)"
    fi
    echo ""
fi

# 7) 번들 압축
echo "7. 번들 압축..."
tar -czf "${OUT}.tar.gz" "$OUT"
echo "   ✅ 번들 생성 완료: ${OUT}.tar.gz"
echo ""

# 8) 요약
echo "=== 증빙 번들 생성 완료 ==="
echo "출력 파일: ${OUT}.tar.gz"
echo "포함 파일:"
ls -lh "$OUT" | tail -n +2 | awk '{print "  - " $9 " (" $5 ")"}'
echo ""
echo "해시 (SHA256):"
shasum -a 256 "${OUT}.tar.gz" | awk '{print "  " $1}'
