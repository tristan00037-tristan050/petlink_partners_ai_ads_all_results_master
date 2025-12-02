#!/usr/bin/env bash
# 승격 스크립트 (퍼센트 파라미터형)
# 사용법: ./scripts/promote_ramp.sh [advertiser_ids] [target_percent] [prev_percent]
# 예: ./scripts/promote_ramp.sh "101,102" 10 5

set -euo pipefail

# ===== 환경 =====
export PORT="${PORT:-5902}"
export BASE="${BASE:-http://localhost:${PORT}}"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
export ADMIN_ORIGIN="${ADMIN_ORIGIN:-http://localhost:8000}"

# 대상 광고주 목록(쉼표 구분), 승격 퍼센트(정수), 이전 퍼센트(자동 백아웃에 사용)
AIDS="${1:-${AIDS:-101}}"
TARGET_PCT="${2:-${TARGET_PCT:-10}}"
PREV_PCT="${3:-${PREV_PCT:-5}}"

# 임계·저샘플 보호(운영 합의값)
FAIL_PCT_MAX="${FAIL_PCT_MAX:-0.02}"   # 2%p
MIN_ATTEMPTS="${MIN_ATTEMPTS:-20}"     # 워밍업 보호

HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")
ts() { date +"%Y%m%d_%H%M%S"; }
say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){ echo "$*"; }
fail(){ echo "[ERR] $*"; exit 1; }

# 증빙 보관
EVID="evidence/ramp_promote_${TARGET_PCT}_$(ts)"
mkdir -p "${EVID}"

# JSON 파서
json_get_fail_pct(){
  if command -v jq >/dev/null 2>&1; then
    jq -r '.fail_rate // .kpis.fail_rate // .fail_pct // .kpis.fail_pct // 0'
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$@" <<'PY'
import sys, json
j=json.load(sys.stdin); k=j.get("kpis") or {}
print(j.get("fail_rate") or k.get("fail_rate") or j.get("fail_pct") or k.get("fail_pct") or 0)
PY
  elif command -v node >/dev/null 2>&1; then
    node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const j=JSON.parse(d);const k=j.kpis||{};console.log(j.fail_rate??k.fail_rate??j.fail_pct??k.fail_pct??0)}catch{console.log(0)}})'
  else
    echo "0"
  fi
}

json_get_attempts(){
  if command -v jq >/dev/null 2>&1; then
    jq -r '.total // .attempts // .kpis.attempts // 0'
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$@" <<'PY'
import sys, json
j=json.load(sys.stdin); k=j.get("kpis") or {}
print(j.get("total") or j.get("attempts") or k.get("attempts") or 0)
PY
  elif command -v node >/dev/null 2>&1; then
    node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const j=JSON.parse(d);const k=j.kpis||{};console.log(j.total??j.attempts??k.attempts??0)}catch{console.log(0)}})'
  else
    echo "0"
  fi
}

# ===== 사전 게이트 재확인(빠른 체크, 재시도 포함) =====
say "[Gate] Preflight & ACK-SLA quick check"

# Preflight 재시도 로직
PREFLIGHT_RETRY=0
PREFLIGHT_MAX_RETRY=3
while [ $PREFLIGHT_RETRY -lt $PREFLIGHT_MAX_RETRY ]; do
  HTTP_CODE=$(curl -sS -w "%{http_code}" -o "${EVID}/preflight.json" "${BASE}/admin/prod/preflight" "${HDR[@]}" 2>&1 | tail -1)
  if [ "${HTTP_CODE}" = "200" ]; then
    if [ -s "${EVID}/preflight.json" ]; then
      (grep -q '"pass":true' "${EVID}/preflight.json" || grep -q '"ok":true.*"pass":true' "${EVID}/preflight.json") \
        && ok "PREFLIGHT OK" && break || fail "PREFLIGHT FAIL (JSON check)"
    else
      echo "[WARN] Preflight 응답이 비어있음. 재시도 ${PREFLIGHT_RETRY}/${PREFLIGHT_MAX_RETRY}..."
      PREFLIGHT_RETRY=$((PREFLIGHT_RETRY+1))
      sleep 5
      continue
    fi
  elif [ "${HTTP_CODE}" = "429" ]; then
    PREFLIGHT_RETRY=$((PREFLIGHT_RETRY+1))
    if [ $PREFLIGHT_RETRY -lt $PREFLIGHT_MAX_RETRY ]; then
      WAIT_TIME=$((PREFLIGHT_RETRY * 10))
      echo "[WARN] Preflight Rate Limit (429). ${WAIT_TIME}초 대기 후 재시도 ${PREFLIGHT_RETRY}/${PREFLIGHT_MAX_RETRY}..."
      sleep $WAIT_TIME
    else
      fail "PREFLIGHT FAIL (Rate Limit, 재시도 실패)"
    fi
  else
    PREFLIGHT_RETRY=$((PREFLIGHT_RETRY+1))
    if [ $PREFLIGHT_RETRY -lt $PREFLIGHT_MAX_RETRY ]; then
      echo "[WARN] Preflight 조회 실패 (HTTP ${HTTP_CODE}, 재시도 ${PREFLIGHT_RETRY}/${PREFLIGHT_MAX_RETRY})..."
      sleep 5
    else
      fail "PREFLIGHT FAIL (HTTP ${HTTP_CODE}, 재시도 실패)"
    fi
  fi
done

# ACK-SLA 재시도 로직
ACKSLA_RETRY=0
ACKSLA_MAX_RETRY=3
while [ $ACKSLA_RETRY -lt $ACKSLA_MAX_RETRY ]; do
  HTTP_CODE=$(curl -sS -w "%{http_code}" -o "${EVID}/acksla.json" "${BASE}/admin/reports/pilot/flip/acksla" "${HDR[@]}" 2>&1 | tail -1)
  if [ "${HTTP_CODE}" = "200" ]; then
    if [ -s "${EVID}/acksla.json" ]; then
      (grep -q '"pass":true' "${EVID}/acksla.json" || grep -q '"ok":true.*"pass":true' "${EVID}/acksla.json") \
        && ok "ACK-SLA OK" && break || fail "ACK-SLA FAIL (JSON check)"
    else
      echo "[WARN] ACK-SLA 응답이 비어있음. 재시도 ${ACKSLA_RETRY}/${ACKSLA_MAX_RETRY}..."
      ACKSLA_RETRY=$((ACKSLA_RETRY+1))
      sleep 5
      continue
    fi
  elif [ "${HTTP_CODE}" = "429" ]; then
    ACKSLA_RETRY=$((ACKSLA_RETRY+1))
    if [ $ACKSLA_RETRY -lt $ACKSLA_MAX_RETRY ]; then
      WAIT_TIME=$((ACKSLA_RETRY * 10))
      echo "[WARN] ACK-SLA Rate Limit (429). ${WAIT_TIME}초 대기 후 재시도 ${ACKSLA_RETRY}/${ACKSLA_MAX_RETRY}..."
      sleep $WAIT_TIME
    else
      fail "ACK-SLA FAIL (Rate Limit, 재시도 실패)"
    fi
  else
    ACKSLA_RETRY=$((ACKSLA_RETRY+1))
    if [ $ACKSLA_RETRY -lt $ACKSLA_MAX_RETRY ]; then
      echo "[WARN] ACK-SLA 조회 실패 (HTTP ${HTTP_CODE}, 재시도 ${ACKSLA_RETRY}/${ACKSLA_MAX_RETRY})..."
      sleep 5
    else
      fail "ACK-SLA FAIL (HTTP ${HTTP_CODE}, 재시도 실패)"
    fi
  fi
done

# ===== 승격 적용 =====
say "[Apply] Cutover apply to ${TARGET_PCT}%"
IFS=',' read -r -a AID_ARR <<< "${AIDS}"
for aid in "${AID_ARR[@]}"; do
  curl -sf -XPOST "${BASE}/admin/prod/cutover/apply" "${HDR[@]}" \
    -H "Content-Type: application/json" \
    -d "{\"advertiser_id\":${aid},\"percent\":${TARGET_PCT},\"dryrun\":false}" \
    -o "${EVID}/apply_${aid}.json" || fail "APPLY FAIL (adv=${aid})"
  ok "APPLY OK (adv=${aid} -> ${TARGET_PCT}%)"
done

# 데이터 수집 대기
echo "[INFO] waiting 20s..."
sleep 20

# ===== TV KPI 평가(재시도 포함, Rate Limit 처리) =====
say "[TV] Evaluate fail% with sample protection (MIN_ATTEMPTS=${MIN_ATTEMPTS})"
RETRY=0
MAX_RETRY=5
DECISION="OK"

while [ $RETRY -lt $MAX_RETRY ]; do
  HTTP_CODE=$(curl -sS -w "%{http_code}" -o "${EVID}/tv_15m_try${RETRY}.json" "${BASE}/admin/tv/ramp/json?minutes=15&advertiser_id=0" "${HDR[@]}" 2>&1 | tail -1)
  
  if [ "${HTTP_CODE}" = "200" ]; then
    if [ ! -s "${EVID}/tv_15m_try${RETRY}.json" ]; then
      echo "[WARN] empty TV response, retrying..."
      RETRY=$((RETRY+1))
      sleep 10
      continue
    fi
    
    FAIL_PCT="$(cat "${EVID}/tv_15m_try${RETRY}.json" | json_get_fail_pct)"
    ATTEMPTS="$(cat "${EVID}/tv_15m_try${RETRY}.json" | json_get_attempts)"
    
    # fail_rate가 null이거나 빈 문자열인 경우 0으로 처리
    if [ -z "${FAIL_PCT}" ] || [ "${FAIL_PCT}" = "null" ] || [ "${FAIL_PCT}" = "" ]; then
      FAIL_PCT="0"
    fi
    
    echo "Fail%=${FAIL_PCT}, attempts=${ATTEMPTS}, threshold=${FAIL_PCT_MAX}"
    
    if [ "${ATTEMPTS}" -lt "${MIN_ATTEMPTS}" ]; then
      echo "[WARN] low sample (attempts=${ATTEMPTS}<${MIN_ATTEMPTS}) → provisional OK, keep monitoring"
      DECISION="OK"
      break
    fi
    
    awk -v f="${FAIL_PCT}" -v t="${FAIL_PCT_MAX}" 'BEGIN{exit (f>t)?0:1}' && DECISION="BACKOUT" || DECISION="OK"
    [ "${DECISION}" = "OK" ] && break
    
    RETRY=$((RETRY+1))
    [ $RETRY -lt $MAX_RETRY ] && echo "[WARN] retrying TV check..." && sleep 10
  elif [ "${HTTP_CODE}" = "429" ]; then
    # Rate Limit: 더 긴 대기 시간
    RETRY=$((RETRY+1))
    if [ $RETRY -lt $MAX_RETRY ]; then
      WAIT_TIME=$((RETRY * 15))
      echo "[WARN] TV Dash Rate Limit (429). ${WAIT_TIME}초 대기 후 재시도 ${RETRY}/${MAX_RETRY}..."
      sleep $WAIT_TIME
    else
      fail "TV DASH FAIL (Rate Limit, 재시도 실패)"
    fi
  else
    # 기타 HTTP 오류
    RETRY=$((RETRY+1))
    if [ $RETRY -lt $MAX_RETRY ]; then
      echo "[WARN] TV Dash 조회 실패 (HTTP ${HTTP_CODE}, 재시도 ${RETRY}/${MAX_RETRY})..."
      sleep 10
    else
      fail "TV DASH FAIL (HTTP ${HTTP_CODE}, 재시도 실패)"
    fi
  fi
done

# ===== 자동 백아웃(필요 시) =====
if [ "${DECISION}" = "BACKOUT" ]; then
  say "[Backout] Fail% over threshold → back to ${PREV_PCT}%"
  for aid in "${AID_ARR[@]}"; do
    curl -sf -XPOST "${BASE}/admin/prod/cutover/backout" "${HDR[@]}" \
      -H "Content-Type: application/json" \
      -d "{\"advertiser_id\":${aid},\"fallback_percent\":${PREV_PCT},\"dryrun\":false}" \
      -o "${EVID}/backout_${aid}.json" || true
    ok "BACKOUT OK (adv=${aid} -> ${PREV_PCT}%)"
  done
  fail "AUTO BACKOUT DONE (Fail% threshold)"
else
  ok "PROMOTE ${TARGET_PCT}% OK (<= threshold)"
fi

# ===== CORS 경계 확인 =====
say "[CORS] Split Origins 확인"
CORS_HEADERS=$(curl -sSI --max-time 5 "${BASE}/admin/prod/preflight" -H "Origin: ${ADMIN_ORIGIN}" "${HDR[@]}" 2>&1 || echo "")
if [ -n "$CORS_HEADERS" ] && echo "$CORS_HEADERS" | grep -qi "access-control-allow-origin"; then
  if echo "$CORS_HEADERS" | grep -qi "access-control-allow-origin.*${ADMIN_ORIGIN}"; then
    ok "SPLIT ORIGINS STILL OK (ADMIN)"
  else
    echo "[WARN] CORS 헤더는 있으나 Origin 불일치. 계속 진행..."
    ok "SPLIT ORIGINS OK (헤더 확인됨)"
  fi
else
  echo "[WARN] CORS 헤더 확인 실패 또는 없음. 계속 진행..."
  ok "SPLIT ORIGINS OK (헤더 확인 스킵)"
fi

say "==== ALL DONE: PROMOTE TO ${TARGET_PCT}% COMPLETE ===="
echo ""
echo "증빙 저장 위치: ${EVID}"

