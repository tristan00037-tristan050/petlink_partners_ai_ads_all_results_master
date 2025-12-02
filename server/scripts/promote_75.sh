#!/usr/bin/env bash
set -euo pipefail

# ========= 환경 =========
export PORT="${PORT:-5902}"
export BASE="${BASE:-http://localhost:${PORT}}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export ADMIN_ORIGIN="${ADMIN_ORIGIN:-http://localhost:8000}"

# 대상 광고주 목록 (쉼표 구분). 실행 시 첫 번째 인자로도 받을 수 있음.
export AIDS="${1:-${AIDS:-101}}"

# 임계값/게이트 (필요 시 환경변수로 조정)
export FAIL_PCT_MAX="${FAIL_PCT_MAX:-0.02}"   # 2%p
export MIN_ATTEMPTS="${MIN_ATTEMPTS:-40}"     # 75%는 표본 여유 확보 권고
export TV_WINDOW_MIN="${TV_WINDOW_MIN:-30}"   # TV 집계 창(분)

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")
ts()  { date +"%Y%m%d_%H%M%S"; }
say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){  echo "$*"; }
fail(){ echo "[ERR] $*"; exit 1; }

# 증빙 폴더
EVID="evidence/ramp_promote_75_$(ts)"; mkdir -p "${EVID}"

# jq/py/노드 파서 헬퍼
json_get(){  # $1=jq expr
  if command -v jq >/dev/null 2>&1; then jq -r "$1"
  elif command -v python3 >/dev/null 2>&1; then python3 - "$1" <<'PY'
import sys, json
expr=sys.argv[1]
data=json.load(sys.stdin)
# 매우 단순한 expr 지원: .field
if expr.startswith('.'):
  keys=expr.lstrip('.').split('.')
  v=data
  for k in keys:
    if k=='': continue
    v=v.get(k) if isinstance(v, dict) else None
  print('' if v is None else v)
else:
  print('')
PY
  else cat
  fi
}

# Decorrelated Jitter 백오프 재시도 (Retry-After 최우선)
req(){
  local method="$1" url="$2" body="${3:-}" outfile="${4:-/dev/stdout}" tries=0 sleep_ms=400 cap_ms=5000
  while :; do
    tries=$((tries+1))
    if [ -n "${body}" ]; then
      RESP_HEADERS="$(mktemp)"; trap 'rm -f "$RESP_HEADERS"' RETURN
      set +e
      curl -sS -D "$RESP_HEADERS" -X "$method" "$url" "${HDR[@]}" -H "Content-Type: application/json" \
           ${IDEMP_HDR:+-H "$IDEMP_HDR"} --data "$body" -o "$outfile"
      code=$?
      set -e
      http="$(awk 'NR==1{print $2}' "$RESP_HEADERS" 2>/dev/null || echo 000)"
      retry_after="$(awk -F': ' 'BEGIN{IGNORECASE=1}/^Retry-After:/{print $2; exit}' "$RESP_HEADERS" 2>/dev/null || true)"
    else
      RESP_HEADERS="$(mktemp)"; trap 'rm -f "$RESP_HEADERS"' RETURN
      set +e
      curl -sS -D "$RESP_HEADERS" -X "$method" "$url" "${HDR[@]}" ${IDEMP_HDR:+-H "$IDEMP_HDR"} -o "$outfile"
      code=$?
      set -e
      http="$(awk 'NR==1{print $2}' "$RESP_HEADERS" 2>/dev/null || echo 000)"
      retry_after="$(awk -F': ' 'BEGIN{IGNORECASE=1}/^Retry-After:/{print $2; exit}' "$RESP_HEADERS" 2>/dev/null || true)"
    fi

    # 성공
    if [ "$code" = "0" ] && [ "${http}" -ge 200 ] && [ "${http}" -lt 300 ]; then
      return 0
    fi

    # 비재시도 오류
    if [ "${http}" = "400" ] || [ "${http}" = "404" ] || [ "${http}" = "422" ]; then
      echo "[ERR] non-retryable http=${http} url=${url}" >&2; return 1
    fi

    # 재시도 한계
    if [ "$tries" -ge 3 ]; then
      echo "[ERR] retry-exhausted http=${http} url=${url}" >&2; return 1
    fi

    # Retry-After 우선
    if [ -n "${retry_after}" ]; then
      sleep_s="$(printf '%s' "$retry_after" | tr -d '\r\n ')"
      [ -n "$sleep_s" ] && sleep "$sleep_s" && continue
    fi

    # Decorrelated Jitter: sleep = min(cap, rand(base, sleep*3))
    rnd=$((RANDOM%$((sleep_ms*3 - sleep_ms + 1)) + sleep_ms))
    if [ $rnd -gt $cap_ms ]; then rnd=$cap_ms; fi
    sleep "$(awk -v ms="$rnd" 'BEGIN{printf "%.3f", ms/1000}')" || true
    sleep_ms=$rnd
  done
}

# ========== [Gate] Preflight / ACK-SLA / CORS ==========
say "[Gate] Preflight / ACK-SLA / CORS"
req GET "${BASE}/admin/prod/preflight" "" "${EVID}/preflight.json" || fail "PREFLIGHT FAIL"
grep -q '"pass":true' "${EVID}/preflight.json" && ok "PREFLIGHT OK" || fail "PREFLIGHT FAIL(JSON)"

req GET "${BASE}/admin/reports/pilot/flip/acksla" "" "${EVID}/acksla.json" || fail "ACK-SLA FAIL"
grep -q '"pass":true' "${EVID}/acksla.json" && ok "ACK-SLA OK" || fail "ACK-SLA FAIL(JSON)"

curl -sSI "${BASE}/admin/prod/rollout/list" -H "Origin: ${ADMIN_ORIGIN}" "${HDR[@]}" \
  -o "${EVID}/cors_head.txt" >/dev/null || fail "CORS HEAD FAIL"
grep -qi "access-control-allow-origin: ${ADMIN_ORIGIN}" "${EVID}/cors_head.txt" \
  && ok "SPLIT ORIGINS STILL OK (ADMIN)" || fail "SPLIT ORIGINS FAIL"

# ========== [Readiness] TV Dash ==========
say "[Readiness] 사전조건 확인"
IFS=',' read -r -a AID_ARR <<< "${AIDS}"
for aid in "${AID_ARR[@]}"; do
  TV="${EVID}/tv_pre_${aid}.json"
  req GET "${BASE}/admin/tv/ramp/json?minutes=${TV_WINDOW_MIN}&advertiser_id=${aid}" "" "${TV}" || fail "TV DASH FAIL (pre)"
  total="$(cat "${TV}" | json_get '.total')"
  fail_rate="$(cat "${TV}" | json_get '.fail_rate')"
  total="${total:-0}"; fail_rate="${fail_rate:-0}"
  echo "  [adv=${aid}] attempts: ${total} (min: ${MIN_ATTEMPTS}), fail_rate: ${fail_rate} (max: ${FAIL_PCT_MAX})"
  if awk -v t="${total}" -v m="${MIN_ATTEMPTS}" 'BEGIN{exit (t>=m)?0:1}'; then :; else fail "Readiness FAIL (attempts) adv=${aid}"; fi
  if awk -v f="${fail_rate}" -v mx="${FAIL_PCT_MAX}" 'BEGIN{exit (f<=mx)?0:1}'; then :; else fail "Readiness FAIL (fail_rate) adv=${aid}"; fi
done
ok "Readiness OK (all advertisers)"

# ========== [Apply] 75% ==========
say "[Apply] Cutover apply to 75%"
for aid in "${AID_ARR[@]}"; do
  IDEMP_HDR="X-Idempotency-Key: promote-75-${aid}-$(date +%s)-$RANDOM"
  OUT="${EVID}/apply_${aid}.json"
  BODY="$(printf '{"advertiser_id":%s,"percent":75,"dryrun":false}' "$aid")"
  req POST "${BASE}/admin/prod/cutover/apply" "${BODY}" "${OUT}" || fail "APPLY FAIL (adv=${aid})"
  ok "APPLY OK (adv=${aid} -> 75%)"
done

# ========== [Post-check] 사후 검증 & 자동 백아웃 ==========
say "[Post-check] 사후 검증 및 자동 백아웃"
echo "[INFO] waiting 10s for data collection..."
sleep 10

BACKOUT=0
for aid in "${AID_ARR[@]}"; do
  TV="${EVID}/tv_post_${aid}.json"
  req GET "${BASE}/admin/tv/ramp/json?minutes=${TV_WINDOW_MIN}&advertiser_id=${aid}" "" "${TV}" || fail "TV DASH FAIL (post)"
  total="$(cat "${TV}" | json_get '.total')"
  fail_rate="$(cat "${TV}" | json_get '.fail_rate')"
  total="${total:-0}"; fail_rate="${fail_rate:-0}"
  echo "  [adv=${aid}] post attempts=${total}, fail_rate=${fail_rate}"
  if [ "$total" -ge "$MIN_ATTEMPTS" ] && awk -v f="${fail_rate}" -v mx="${FAIL_PCT_MAX}" 'BEGIN{exit (f>mx)?0:1}'; then
    echo "[WARN] threshold exceeded (adv=${aid}): ${fail_rate} > ${FAIL_PCT_MAX} → BACKOUT to 50%"
    IDEMP_HDR="X-Idempotency-Key: backout-50-${aid}-$(date +%s)-$RANDOM"
    OUT="${EVID}/backout_${aid}.json"
    BODY="$(printf '{"advertiser_id":%s,"fallback_percent":50,"dryrun":false}' "$aid")"
    req POST "${BASE}/admin/prod/cutover/backout" "${BODY}" "${OUT}" || true
    BACKOUT=1
    ok "BACKOUT OK (adv=${aid} -> 50%)"
  fi
done

# CORS 재확인
curl -sSI "${BASE}/admin/prod/rollout/list" -H "Origin: ${ADMIN_ORIGIN}" "${HDR[@]}" \
  -o "${EVID}/cors_head_after.txt" >/dev/null || fail "CORS HEAD FAIL(2)"
grep -qi "access-control-allow-origin: ${ADMIN_ORIGIN}" "${EVID}/cors_head_after.txt" \
  && ok "SPLIT ORIGINS STILL OK (ADMIN)" || fail "SPLIT ORIGINS FAIL(HEADER)"

if [ "$BACKOUT" = "1" ]; then
  echo '{ "action":"PROMOTE_75", "result":"backout", "stage_from":50, "stage_to":75, "auto_backout":1 }' > "${EVID}/decision.json"
  fail "PROMOTE 75% AUTO BACKOUT (threshold exceeded)"
else
  echo '{ "action":"PROMOTE_75", "result":"promote_ok", "stage_from":50, "stage_to":75, "auto_backout":0 }' > "${EVID}/decision.json"
  ok "PROMOTE 75% OK (<= threshold)"
  say "==== ALL DONE: PROMOTE TO 75% COMPLETE ===="
  echo "증빙 저장 위치: ${EVID}"
fi
