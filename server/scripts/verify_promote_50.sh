#!/usr/bin/env bash
# 50% 승격 실행 직후 확인 스크립트
# 사용법: ./scripts/verify_promote_50.sh [evidence_directory]
# 예: ./scripts/verify_promote_50.sh evidence/ramp_promote_50_20251116_163000

set -euo pipefail

EVID_DIR="${1:-}"
if [ -z "$EVID_DIR" ]; then
  EVID_DIR=$(find evidence -type d -name "ramp_promote_50_*" 2>/dev/null | sort -r | head -1)
fi

if [ -z "$EVID_DIR" ] || [ ! -d "$EVID_DIR" ]; then
  echo "[ERR] 증빙 디렉토리를 찾을 수 없습니다"
  echo "사용법: ./scripts/verify_promote_50.sh [evidence_directory]"
  exit 1
fi

say(){ printf "\n\033[1m%s\033[0m\n" "$*"; }
ok(){ echo "  ✅ $*"; }
fail(){ echo "  ❌ $*"; return 1; }
warn(){ echo "  ⚠️  $*"; }

say "50% 승격 실행 직후 확인"
echo "증빙 디렉토리: ${EVID_DIR}"
echo ""

# ===== 1. decision.json 확인 =====
say "[1] decision.json 확인"
if [ -f "${EVID_DIR}/decision.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    cat "${EVID_DIR}/decision.json" | jq '.'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "${EVID_DIR}/decision.json"
  else
    cat "${EVID_DIR}/decision.json"
  fi
  ok "decision.json 확인 완료"
else
  fail "decision.json 없음"
fi

# ===== 2. metrics.jsonl 확인 =====
say "[2] metrics.jsonl 확인"
if [ -f "${EVID_DIR}/metrics.jsonl" ]; then
  if command -v jq >/dev/null 2>&1; then
    cat "${EVID_DIR}/metrics.jsonl" | jq -s '.'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c "
import sys, json
for line in sys.stdin:
    if line.strip():
        print(json.dumps(json.loads(line), indent=2))
" < "${EVID_DIR}/metrics.jsonl"
  else
    cat "${EVID_DIR}/metrics.jsonl"
  fi
  ok "metrics.jsonl 확인 완료"
else
  warn "metrics.jsonl 없음"
fi

# ===== 3. logs.ndjson 확인 (비정상 응답만) =====
say "[3] logs.ndjson 확인 (비정상 응답)"
if [ -f "${EVID_DIR}/logs.ndjson" ]; then
  NON_2XX=$(cat "${EVID_DIR}/logs.ndjson" | grep -v '"code":"2' || true)
  if [ -z "$NON_2XX" ]; then
    ok "모든 요청이 2xx 응답"
  else
    warn "비정상 응답 발견:"
    echo "$NON_2XX" | head -5
  fi
else
  warn "logs.ndjson 없음"
fi

# ===== 4. CORS 헤더 확인 =====
say "[4] CORS 헤더 확인"
CORS_FILES=$(find "${EVID_DIR}" -name "cors_head*.txt" 2>/dev/null | head -2)
if [ -n "$CORS_FILES" ]; then
  for f in $CORS_FILES; do
    echo "  파일: $(basename "$f")"
    if grep -qi "access-control-allow-origin" "$f" 2>/dev/null; then
      ok "CORS 헤더 확인됨"
      grep -i "access-control-allow-origin" "$f" | head -1
    else
      warn "CORS 헤더 없음"
    fi
  done
else
  warn "CORS 헤더 파일 없음"
fi

# ===== 5. 증빙 파일 목록 =====
say "[5] 증빙 파일 목록"
ls -lh "${EVID_DIR}" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'

say "확인 완료"

