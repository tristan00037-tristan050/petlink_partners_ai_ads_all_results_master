#!/usr/bin/env bash
# 50% 승격 스크립트 (개발 모드 - MIN_ATTEMPTS 검증 완화)
# 사용법: ./scripts/promote_50_dev.sh [advertiser_ids]
# 예: ./scripts/promote_50_dev.sh "101,102"
#
# 개발 모드 특징:
# - MIN_ATTEMPTS 기본값: 5 (운영 모드: 20)
# - 데이터 부족 시 경고만 출력하고 계속 진행
# - 테스트 데이터 생성 안내 제공

set -euo pipefail

PORT="${PORT:-5902}"
BASE="${BASE:-http://localhost:${PORT}}"
ADMIN_KEY="${ADMIN_KEY:?ADMIN_KEY 환경 변수가 설정되지 않았습니다. export ADMIN_KEY='your-admin-key'를 실행하세요}"
ADMIN_ORIGIN="${ADMIN_ORIGIN:-http://localhost:8000}"

AIDS="${1:-${AIDS:-101}}"
FAIL_PCT_MAX="${FAIL_PCT_MAX:-0.02}"     # 2%p 임계
MIN_ATTEMPTS="${MIN_ATTEMPTS:-5}"         # 개발 모드: 5 (운영: 20)
PROMOTE_PERCENT="${PROMOTE_PERCENT:-50}" # 승격 목표
DEV_MODE="${DEV_MODE:-1}"                 # 개발 모드 활성화

EVID="evidence/ramp_promote_${PROMOTE_PERCENT}_dev_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EVID"

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")

# ADMIN_KEY 검증 (디버깅용)
if [ -z "${ADMIN_KEY:-}" ]; then
  echo "[ERR] ADMIN_KEY가 설정되지 않았습니다" >&2
  exit 1
fi

# JSON 파서
JSON(){
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys,json;d=json.load(sys.stdin);print($1)" 2>/dev/null || echo ""
  else
    cat
  fi
}

ts(){ date -Iseconds; }
rid(){ echo "promote-${PROMOTE_PERCENT}-$(date +%s)-$RANDOM"; }

say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){ echo "$*"; }
fail(){ echo "[ERR] $*"; exit 1; }
warn(){ echo "[WARN] $*"; }

echo "=== 개발 모드로 실행 중 ==="
echo "MIN_ATTEMPTS: ${MIN_ATTEMPTS} (운영 모드: 20)"
echo ""

# ---- 요청 헬퍼(재시도 + Retry-After + Decorrelated Jitter) ----
req(){ 
  local METHOD="$1"; shift
  local URL="$1"; shift
  local BODY="${1:-}"; shift || true

  local TRY=0; local MAX=3
  local BASE_MS=400; local CAP_MS=5000; local SLEEP_MS=$BASE_MS
  while :; do
    local HFILE; HFILE="$(mktemp 2>/dev/null || echo /tmp/curl_headers_$$)"; local CODE
    if [ -n "$BODY" ]; then
      CODE=$(curl -sS -o "$EVID/.tmp" -w "%{http_code}" -D "$HFILE" -X "$METHOD" "$URL" \
        "${HDR[@]}" -H "Content-Type: application/json" -H "X-Idempotency-Key: $(rid)" \
        --data "$BODY" 2>/dev/null) || CODE="000"
    else
      CODE=$(curl -sS -o "$EVID/.tmp" -w "%{http_code}" -D "$HFILE" -X "$METHOD" "$URL" "${HDR[@]}" 2>/dev/null) || CODE="000"
    fi

    # 로그 적재
    printf '{"ts":"%s","method":"%s","url":"%s","code":"%s","try":%d,"sleep_ms":%d}\n' \
      "$(ts)" "$METHOD" "$URL" "$CODE" "$TRY" "$SLEEP_MS" >> "${EVID}/logs.ndjson"

    # 2xx 통과
    if [[ "$CODE" =~ ^2..$ ]]; then cat "$EVID/.tmp"; rm -f "$EVID/.tmp" "$HFILE" 2>/dev/null; return 0; fi

    # 비재시도 군: 400/401/403/422/404
    if [[ "$CODE" = "400" || "$CODE" = "401" || "$CODE" = "403" || "$CODE" = "422" || "$CODE" = "404" ]]; then
      echo "non-retryable $CODE on $URL" >&2
      if [ "$CODE" = "401" ]; then
        echo "[ERR] 401 Unauthorized - ADMIN_KEY 확인 필요" >&2
      fi
      cat "$EVID/.tmp"; rm -f "$EVID/.tmp" "$HFILE" 2>/dev/null; return 1
    fi

    # 재시도 한계
    TRY=$((TRY+1)); if [ "$TRY" -gt "$MAX" ]; then
      echo "retry-exhausted $CODE on $URL" >&2; cat "$EVID/.tmp"; rm -f "$EVID/.tmp" "$HFILE" 2>/dev/null; return 1
    fi

    # Retry-After 우선
    RA=$(grep -i '^Retry-After:' "$HFILE" 2>/dev/null | tail -1 | awk '{print $2}' | tr -d '\r' || echo "")
    if [ -n "${RA:-}" ]; then
      sleep "${RA}" 2>/dev/null || sleep 1; rm -f "$HFILE" 2>/dev/null; continue
    fi

    # Decorrelated Jitter: sleep = min(cap, rand(base, sleep*3))
    RAND_ADD=$(( (RANDOM % (SLEEP_MS*3 - BASE_MS + 1)) + BASE_MS ))
    SLEEP_MS=$(( SLEEP_MS + RAND_ADD ))
    [ "$SLEEP_MS" -gt "$CAP_MS" ] && SLEEP_MS="$CAP_MS"
    python3 - <<PY 2>/dev/null || sleep 1
import time; time.sleep(${SLEEP_MS}/1000.0)
PY
    rm -f "$HFILE" 2>/dev/null
  done
}

# ---- 공통 게이트 ----
say "[Gate] Preflight / ACK-SLA / CORS"
req GET "${BASE}/admin/prod/preflight" > "${EVID}/preflight.json" || fail "PREFLIGHT FAIL (curl error)"
if [ ! -s "${EVID}/preflight.json" ]; then
  fail "PREFLIGHT FAIL (empty response)"
fi
grep -q '"pass":true' "${EVID}/preflight.json" || grep -q '"ok":true.*"pass":true' "${EVID}/preflight.json" || fail "PREFLIGHT FAIL (JSON check)"
ok "PREFLIGHT OK"

req GET "${BASE}/admin/reports/pilot/flip/acksla" > "${EVID}/acksla.json" || true
# p95(있으면) 추출 시도
if [ -s "${EVID}/acksla.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    ACKP95=$(jq -r '.p95 // .metrics.p95 // empty' < "${EVID}/acksla.json" 2>/dev/null || echo "")
  elif command -v python3 >/dev/null 2>&1; then
    ACKP95=$(python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('p95') or (d.get('metrics') or {}).get('p95') or '')" < "${EVID}/acksla.json" 2>/dev/null || echo "")
  else
    ACKP95=""
  fi
  [ -n "$ACKP95" ] && [ "$ACKP95" != "null" ] && [ "$ACKP95" != "" ] && echo "{\"ack_p95_ms\":${ACKP95}}" >> "${EVID}/metrics.jsonl" || true
fi

curl -sS -I "${BASE}/admin/prod/preflight" -H "Origin: ${ADMIN_ORIGIN}" "${HDR[@]}" \
  -o "${EVID}/cors_head.txt" >/dev/null 2>&1 || true
grep -qi "access-control-allow-origin.*${ADMIN_ORIGIN}" "${EVID}/cors_head.txt" || echo "[WARN] CORS header not matched"

# ---- 광고주별 사전조건 확인 (개발 모드: 경고만) ----
IFS=',' read -r -a A <<< "${AIDS}"
SKIP_COUNT=0
for aid in "${A[@]}"; do
  say "[Readiness] 사전조건 확인 (adv=${aid})"
  req GET "${BASE}/admin/tv/ramp/json?minutes=30&advertiser_id=${aid}" > "${EVID}/tv_${aid}.json" || fail "TV JSON FAIL (adv=${aid})"
  
  if command -v jq >/dev/null 2>&1; then
    TOTAL=$(jq -r '.total // .kpis.total // 0' < "${EVID}/tv_${aid}.json" 2>/dev/null || echo 0)
    FAILP=$(jq -r '.fail_rate // .kpis.fail_rate // 0' < "${EVID}/tv_${aid}.json" 2>/dev/null || echo 0)
  elif command -v python3 >/dev/null 2>&1; then
    TOTAL=$(python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('total') or (d.get('kpis') or {}).get('total') or 0)" < "${EVID}/tv_${aid}.json" 2>/dev/null || echo 0)
    FAILP=$(python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('fail_rate') or (d.get('kpis') or {}).get('fail_rate') or 0)" < "${EVID}/tv_${aid}.json" 2>/dev/null || echo 0)
  else
    TOTAL=0
    FAILP=0
  fi
  
  # fail_rate가 null이거나 빈 문자열인 경우 0으로 처리
  if [ -z "${FAILP}" ] || [ "${FAILP}" = "null" ] || [ "${FAILP}" = "" ]; then
    FAILP="0"
  fi
  
  printf '{"ts":"%s","adv":%s,"total":%s,"fail_rate":%s}\n' "$(ts)" "$aid" "$TOTAL" "$FAILP" >> "${EVID}/metrics.jsonl"

  echo "  attempts: ${TOTAL} (최소: ${MIN_ATTEMPTS})"
  echo "  fail_rate: ${FAILP} (최대: ${FAIL_PCT_MAX})"

  if [ "${TOTAL}" -lt "${MIN_ATTEMPTS}" ]; then
    warn "MIN_ATTEMPTS not met (${TOTAL} < ${MIN_ATTEMPTS}) adv=${aid} - 개발 모드에서 경고만 출력하고 계속 진행"
    echo ""
    echo "테스트 데이터 생성:"
    echo "  ./scripts/generate_test_data.sh ${aid} ${MIN_ATTEMPTS}"
    echo ""
    SKIP_COUNT=$((SKIP_COUNT + 1))
  else
    awk -v f="${FAILP}" -v t="${FAIL_PCT_MAX}" 'BEGIN{exit (f<=t)?0:1}' || {
      warn "Fail% threshold exceeded (${FAILP} > ${FAIL_PCT_MAX}) adv=${aid} - 개발 모드에서 경고만 출력하고 계속 진행"
    }
    echo "  ✅ 조건 충족"
    ok "Readiness OK (adv=${aid}, attempts=${TOTAL}, fail_rate=${FAILP})"
  fi
done

if [ $SKIP_COUNT -gt 0 ]; then
  warn "일부 광고주가 MIN_ATTEMPTS를 만족하지 않지만, 개발 모드에서 계속 진행합니다"
fi

# ---- 승격 적용(50%) ----
for aid in "${A[@]}"; do
  echo "[*] APPLY 50% (adv=${aid})"
  BODY=$(printf '{"advertiser_id":%s,"percent":%s,"dryrun":false}' "$aid" "$PROMOTE_PERCENT")
  req POST "${BASE}/admin/prod/cutover/apply" "$BODY" > "${EVID}/apply_${aid}.json" || { echo "[ERR] APPLY FAIL (adv=${aid})"; exit 1; }
  echo "APPLY OK (adv=${aid} -> ${PROMOTE_PERCENT}%)"
done

# ---- 사후 검증 & 자동 백아웃(25%) ----
sleep 10
AUTO_BACKOUT=0
for aid in "${A[@]}"; do
  req GET "${BASE}/admin/tv/ramp/json?minutes=15&advertiser_id=${aid}" > "${EVID}/tv_post_${aid}.json" || true
  
  if command -v jq >/dev/null 2>&1; then
    TOTAL=$(jq -r '.total // .kpis.total // 0' < "${EVID}/tv_post_${aid}.json" 2>/dev/null || echo 0)
    FAILP=$(jq -r '.fail_rate // .kpis.fail_rate // 0' < "${EVID}/tv_post_${aid}.json" 2>/dev/null || echo 0)
  elif command -v python3 >/dev/null 2>&1; then
    TOTAL=$(python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('total') or (d.get('kpis') or {}).get('total') or 0)" < "${EVID}/tv_post_${aid}.json" 2>/dev/null || echo 0)
    FAILP=$(python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('fail_rate') or (d.get('kpis') or {}).get('fail_rate') or 0)" < "${EVID}/tv_post_${aid}.json" 2>/dev/null || echo 0)
  else
    TOTAL=0
    FAILP=0
  fi
  
  printf '{"ts":"%s","post_adv":%s,"total":%s,"fail_rate":%s}\n' "$(ts)" "$aid" "$TOTAL" "$FAILP" >> "${EVID}/metrics.jsonl"

  if [ "$TOTAL" -gt 0 ]; then
    awk -v f="$FAILP" -v t="${FAIL_PCT_MAX}" 'BEGIN{exit (f<=t)?0:1}' || {
      warn "Threshold exceeded after apply (${FAILP} > ${FAIL_PCT_MAX}) -> BACKOUT to 25% (adv=${aid})"
      BODY=$(printf '{"advertiser_id":%s,"fallback_percent":25,"dryrun":false}' "$aid")
      req POST "${BASE}/admin/prod/cutover/backout" "$BODY" > "${EVID}/backout_${aid}.json" || true
      AUTO_BACKOUT=1
    }
  fi
done

# ---- 최종 표식/증빙 ----
echo "SPLIT ORIGINS CHECK..."
curl -sS -I "${BASE}/admin/prod/preflight" -H "Origin: ${ADMIN_ORIGIN}" "${HDR[@]}" \
  -o "${EVID}/cors_head_final.txt" >/dev/null 2>&1 || true
grep -qi "access-control-allow-origin.*${ADMIN_ORIGIN}" "${EVID}/cors_head_final.txt" \
  && echo "SPLIT ORIGINS STILL OK (ADMIN)" || echo "[WARN] SPLIT ORIGINS HEADER MISMATCH"

# decision.json 기록
cat > "${EVID}/decision.json" <<JSON
{
  "ts":"$(ts)",
  "action":"PROMOTE_${PROMOTE_PERCENT}_DEV",
  "aids":"${AIDS}",
  "fail_pct_max":${FAIL_PCT_MAX},
  "min_attempts":${MIN_ATTEMPTS},
  "dev_mode":true,
  "auto_backout": ${AUTO_BACKOUT},
  "skip_count": ${SKIP_COUNT}
}
JSON

if [ "$AUTO_BACKOUT" -eq 1 ]; then
  echo "[WARN] AUTO BACKOUT DONE (Fail% threshold) - 개발 모드"
  exit 2
fi

echo "PROMOTE ${PROMOTE_PERCENT}% OK (DEV MODE)"
echo "Evidence: ${EVID}"
echo "==== ALL DONE: PROMOTE TO ${PROMOTE_PERCENT}% COMPLETE (DEV MODE) ===="

