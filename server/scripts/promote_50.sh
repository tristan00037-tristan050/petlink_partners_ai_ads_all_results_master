#!/usr/bin/env bash
# 50% 승격 스크립트 (사전조건 자동 점검 + 자동 백아웃)
# 사용법: ./scripts/promote_50.sh [advertiser_ids]
# 예: ./scripts/promote_50.sh "101,102"

set -euo pipefail

PORT="${PORT:-5902}"
BASE="${BASE:-http://localhost:${PORT}}"
ADMIN_KEY="${ADMIN_KEY:?ADMIN_KEY 환경 변수가 설정되지 않았습니다. export ADMIN_KEY='your-admin-key'를 실행하세요}"
ADMIN_ORIGIN="${ADMIN_ORIGIN:-http://localhost:8000}"

AIDS="${1:-${AIDS:-101}}"
FAIL_PCT_MAX="${FAIL_PCT_MAX:-0.02}"     # 2%p 임계
MIN_ATTEMPTS="${MIN_ATTEMPTS:-20}"       # 저샘플 보호
PROMOTE_PERCENT="${PROMOTE_PERCENT:-50}" # 승격 목표

EVID="evidence/ramp_promote_${PROMOTE_PERCENT}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EVID"

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")

# ADMIN_KEY 검증 (디버깅용)
if [ -z "${ADMIN_KEY:-}" ]; then
  echo "[ERR] ADMIN_KEY가 설정되지 않았습니다" >&2
  echo "      export ADMIN_KEY='your-admin-key'를 실행하세요" >&2
  exit 1
fi

# ADMIN_KEY 디버깅 (선택적)
if [ "${DEBUG:-0}" = "1" ]; then
  echo "[DEBUG] ADMIN_KEY: ${ADMIN_KEY:0:10}..." >&2
  echo "[DEBUG] HDR: ${HDR[*]}" >&2
fi

# JSON 파서 (jq 우선, python3 fallback)
JSON(){
  if command -v jq >/dev/null 2>&1; then
    jq -r "$1"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "import sys,json;d=json.load(sys.stdin);print($1)" 2>/dev/null || echo ""
  else
    cat
  fi
}

ts(){ date -Iseconds 2>/dev/null || date +"%Y-%m-%dT%H:%M:%S%z"; }
rid(){ echo "promote-${PROMOTE_PERCENT}-$(date +%s)-$RANDOM"; }

say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){ echo "$*"; }
fail(){ echo "[ERR] $*"; exit 1; }

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

# ---- 광고주별 사전조건 확인 ----
IFS=',' read -r -a A <<< "${AIDS}"
# 사전/사후 메트릭 수집용 변수 초기화 (bash 3.x 호환)
STAGE_FROM="${STAGE_FROM:-25}"  # 기본 이전 단계 25%
STAGE_TO="${PROMOTE_PERCENT}"

# 메트릭 저장용 임시 파일
ATTEMPTS_BEFORE_FILE="${EVID}/.attempts_before"
ATTEMPTS_AFTER_FILE="${EVID}/.attempts_after"
FAIL_PCT_BEFORE_FILE="${EVID}/.fail_pct_before"
FAIL_PCT_AFTER_FILE="${EVID}/.fail_pct_after"
> "${ATTEMPTS_BEFORE_FILE}"
> "${ATTEMPTS_AFTER_FILE}"
> "${FAIL_PCT_BEFORE_FILE}"
> "${FAIL_PCT_AFTER_FILE}"

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
  
  # 사전 메트릭 저장 (bash 3.x 호환)
  echo "${aid}:${TOTAL}" >> "${ATTEMPTS_BEFORE_FILE}"
  echo "${aid}:${FAILP}" >> "${FAIL_PCT_BEFORE_FILE}"

  echo "  attempts: ${TOTAL} (최소: ${MIN_ATTEMPTS})"
  echo "  fail_rate: ${FAILP} (최대: ${FAIL_PCT_MAX})"

  if [ "${TOTAL}" -lt "${MIN_ATTEMPTS}" ]; then
    echo ""
    echo "[ERR] MIN_ATTEMPTS not met (${TOTAL} < ${MIN_ATTEMPTS}) adv=${aid}"
    echo ""
    echo "해결 방법:"
    echo "  1. TV Dash 데이터 확인:"
    echo "     curl -sS '${BASE}/admin/tv/ramp/json?minutes=30&advertiser_id=${aid}' \\"
    echo "       -H 'X-Admin-Key: \${ADMIN_KEY}' | python3 -m json.tool"
    echo ""
    echo "  2. subs_autoroute_journal 테이블에 데이터가 있는지 확인:"
    echo "     psql \"\${DATABASE_URL}\" -c \"SELECT COUNT(*) FROM subs_autoroute_journal WHERE advertiser_id=${aid} AND created_at >= now() - interval '30 minutes';\""
    echo ""
    echo "  3. 데이터가 있는 광고주 확인:"
    echo "     psql \"\${DATABASE_URL}\" -c \"SELECT advertiser_id, COUNT(*) as total FROM subs_autoroute_journal WHERE created_at >= now() - interval '30 minutes' GROUP BY advertiser_id ORDER BY total DESC LIMIT 5;\""
    echo ""
    echo "  4. MIN_ATTEMPTS 임시 낮추기 (권장하지 않음):"
    echo "     export MIN_ATTEMPTS=10"
    echo ""
    fail "MIN_ATTEMPTS not met (${TOTAL} < ${MIN_ATTEMPTS}) adv=${aid}"
  fi
  
  awk -v f="${FAILP}" -v t="${FAIL_PCT_MAX}" 'BEGIN{exit (f<=t)?0:1}' || {
    echo ""
    echo "[ERR] Fail% threshold exceeded (${FAILP} > ${FAIL_PCT_MAX}) adv=${aid}"
    echo ""
    echo "해결 방법:"
    echo "  1. TV Dash 상세 확인:"
    echo "     cat ${EVID}/tv_${aid}.json | python3 -m json.tool"
    echo ""
    echo "  2. 최근 오류 로그 확인:"
    echo "     tail -100 .petlink.out | grep -i 'error\\|fail\\|${aid}'"
    echo ""
    fail "Fail% threshold exceeded (${FAILP} > ${FAIL_PCT_MAX}) adv=${aid}"
  }
  
  echo "  ✅ 조건 충족"
  
  ok "Readiness OK (adv=${aid}, attempts=${TOTAL}, fail_rate=${FAILP})"
done

# ---- 승격 적용(50%) ----
say "[Apply] Cutover apply to ${PROMOTE_PERCENT}%"
for aid in "${A[@]}"; do
  BODY=$(printf '{"advertiser_id":%s,"percent":%s,"dryrun":false}' "$aid" "$PROMOTE_PERCENT")
  req POST "${BASE}/admin/prod/cutover/apply" "$BODY" > "${EVID}/apply_${aid}.json" || fail "APPLY FAIL (adv=${aid})"
  ok "APPLY OK (adv=${aid} -> ${PROMOTE_PERCENT}%)"
done

# ---- 사후 검증 & 자동 백아웃(25%) ----
say "[Post-check] 사후 검증 및 자동 백아웃"
echo "[INFO] waiting 10s for data collection..."
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
  
  # fail_rate가 null이거나 빈 문자열인 경우 0으로 처리
  if [ -z "${FAILP}" ] || [ "${FAILP}" = "null" ] || [ "${FAILP}" = "" ]; then
    FAILP="0"
  fi
  
  printf '{"ts":"%s","post_adv":%s,"total":%s,"fail_rate":%s}\n' "$(ts)" "$aid" "$TOTAL" "$FAILP" >> "${EVID}/metrics.jsonl"
  
  # 사후 메트릭 저장 (bash 3.x 호환)
  echo "${aid}:${TOTAL}" >> "${ATTEMPTS_AFTER_FILE}"
  echo "${aid}:${FAILP}" >> "${FAIL_PCT_AFTER_FILE}"

  if [ "${TOTAL}" -gt 0 ]; then
    awk -v f="${FAILP}" -v t="${FAIL_PCT_MAX}" 'BEGIN{exit (f<=t)?0:1}' || {
      echo "[WARN] Threshold exceeded after apply (${FAILP} > ${FAIL_PCT_MAX}) -> BACKOUT to 25% (adv=${aid})"
      BODY=$(printf '{"advertiser_id":%s,"fallback_percent":25,"dryrun":false}' "$aid")
      req POST "${BASE}/admin/prod/cutover/backout" "$BODY" > "${EVID}/backout_${aid}.json" || true
      AUTO_BACKOUT=1
    }
  else
    echo "[WARN] Low sample after apply (total=${TOTAL}) -> keep monitoring (adv=${aid})"
  fi
done

# ---- 최종 표식/증빙 ----
say "[CORS] Split Origins 확인"
curl -sS -I "${BASE}/admin/prod/preflight" -H "Origin: ${ADMIN_ORIGIN}" "${HDR[@]}" \
  -o "${EVID}/cors_head_final.txt" >/dev/null 2>&1 || true
grep -qi "access-control-allow-origin.*${ADMIN_ORIGIN}" "${EVID}/cors_head_final.txt" \
  && ok "SPLIT ORIGINS STILL OK (ADMIN)" || echo "[WARN] SPLIT ORIGINS HEADER MISMATCH"

# decision.json 기록 (보강된 스키마)
# attempts_before/after, fail_pct_before/after JSON 객체 생성 (bash 3.x 호환)
ATTEMPTS_BEFORE_JSON="{"
ATTEMPTS_AFTER_JSON="{"
FAIL_PCT_BEFORE_JSON="{"
FAIL_PCT_AFTER_JSON="{"
FIRST=1
for aid in "${A[@]}"; do
  if [ "$FIRST" -eq 0 ]; then
    ATTEMPTS_BEFORE_JSON="${ATTEMPTS_BEFORE_JSON},"
    ATTEMPTS_AFTER_JSON="${ATTEMPTS_AFTER_JSON},"
    FAIL_PCT_BEFORE_JSON="${FAIL_PCT_BEFORE_JSON},"
    FAIL_PCT_AFTER_JSON="${FAIL_PCT_AFTER_JSON},"
  fi
  # 임시 파일에서 값 읽기
  AB=$(grep "^${aid}:" "${ATTEMPTS_BEFORE_FILE}" 2>/dev/null | cut -d: -f2 || echo "0")
  AA=$(grep "^${aid}:" "${ATTEMPTS_AFTER_FILE}" 2>/dev/null | cut -d: -f2 || echo "0")
  FB=$(grep "^${aid}:" "${FAIL_PCT_BEFORE_FILE}" 2>/dev/null | cut -d: -f2 || echo "0")
  FA=$(grep "^${aid}:" "${FAIL_PCT_AFTER_FILE}" 2>/dev/null | cut -d: -f2 || echo "0")
  ATTEMPTS_BEFORE_JSON="${ATTEMPTS_BEFORE_JSON}\"${aid}\":${AB}"
  ATTEMPTS_AFTER_JSON="${ATTEMPTS_AFTER_JSON}\"${aid}\":${AA}"
  FAIL_PCT_BEFORE_JSON="${FAIL_PCT_BEFORE_JSON}\"${aid}\":${FB}"
  FAIL_PCT_AFTER_JSON="${FAIL_PCT_AFTER_JSON}\"${aid}\":${FA}"
  FIRST=0
done
ATTEMPTS_BEFORE_JSON="${ATTEMPTS_BEFORE_JSON}}"
ATTEMPTS_AFTER_JSON="${ATTEMPTS_AFTER_JSON}}"
FAIL_PCT_BEFORE_JSON="${FAIL_PCT_BEFORE_JSON}}"
FAIL_PCT_AFTER_JSON="${FAIL_PCT_AFTER_JSON}}"

# git commit (선택적)
GIT_COMMIT=""
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
fi

cat > "${EVID}/decision.json" <<JSON
{
  "ts":"$(ts)",
  "script_version":"r12.6",
  "git_commit":"${GIT_COMMIT}",
  "action":"PROMOTE_${PROMOTE_PERCENT}",
  "aids":"${AIDS}",
  "stage_from":${STAGE_FROM},
  "stage_to":${STAGE_TO},
  "min_attempts":${MIN_ATTEMPTS},
  "fail_pct_max":${FAIL_PCT_MAX},
  "auto_backout":${AUTO_BACKOUT},
  "attempts_before":${ATTEMPTS_BEFORE_JSON},
  "attempts_after":${ATTEMPTS_AFTER_JSON},
  "fail_pct_before":${FAIL_PCT_BEFORE_JSON},
  "fail_pct_after":${FAIL_PCT_AFTER_JSON}
}
JSON

if [ "$AUTO_BACKOUT" -eq 1 ]; then
  fail "AUTO BACKOUT DONE (Fail% threshold)"
fi

ok "PROMOTE ${PROMOTE_PERCENT}% OK (<= threshold)"
say "==== ALL DONE: PROMOTE TO ${PROMOTE_PERCENT}% COMPLETE ===="
echo ""
echo "증빙 저장 위치: ${EVID}"

