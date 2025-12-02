#!/usr/bin/env bash
# run_and_verify.sh - 원클릭 스크립트 실행 + 통과 로그 자동 검증

set -euo pipefail

LOG_FILE=".go_live_r4r5_run.log"
SERVER_LOG=".petlink.out"

echo "=== 원클릭 스크립트 실행 및 검증 ==="
echo ""

# 스크립트 실행 권한 부여 후 실행
chmod +x scripts/go_live_r4r5_local.sh

echo "[1/3] 스크립트 실행 중..."
./scripts/go_live_r4r5_local.sh 2>&1 | tee "$LOG_FILE"

echo ""
echo "[2/3] 통과 체크포인트 자동 스캔"
echo "=== PASS CHECK ==="

# 통과 체크포인트 검색
PASS_KEYWORDS=(
    "health OK"
    "IDEMPOTENCY REPLAY OK"
    "OPENAPI SPEC OK"
    "SWAGGER UI OK"
    "OUTBOX PEEK OK"
    "OUTBOX FLUSH OK"
    "HOUSEKEEPING OK"
    "TTL CLEANUP VERIFIED"
    "DLQ API OK"
)

PASS_COUNT=0
MISSING=()

for keyword in "${PASS_KEYWORDS[@]}"; do
    if grep -qi "$keyword" "$LOG_FILE" 2>/dev/null; then
        echo "✅ $keyword"
        ((PASS_COUNT++))
    else
        echo "❌ $keyword (누락)"
        MISSING+=("$keyword")
    fi
done

echo ""
echo "[3/3] 검증 결과"
echo "통과: $PASS_COUNT / ${#PASS_KEYWORDS[@]}"

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo "⚠️  누락된 체크포인트:"
    printf '   - %s\n' "${MISSING[@]}"
    echo ""
    echo "=== 오류 분석 ==="
    
    # 로그 파일의 마지막 200줄
    if [ -f "$LOG_FILE" ]; then
        echo "--- $LOG_FILE (마지막 200줄) ---"
        tail -n 200 "$LOG_FILE" | grep -E "ERR|WARN|error|failed|실패" -i || tail -n 50 "$LOG_FILE"
    fi
    
    # 서버 로그의 마지막 200줄
    if [ -f "$SERVER_LOG" ]; then
        echo ""
        echo "--- $SERVER_LOG (마지막 200줄) ---"
        tail -n 200 "$SERVER_LOG" | grep -E "ERR|WARN|error|failed|실패" -i || tail -n 50 "$SERVER_LOG"
    fi
    
    echo ""
    echo "=== 수정 제안 ==="
    
    # 누락된 항목별 수정 제안
    for missing in "${MISSING[@]}"; do
        case "$missing" in
            "health OK")
                echo "[health OK 누락]"
                echo "  - 서버가 정상 기동하지 않았습니다."
                echo "  - 확인: tail -f $SERVER_LOG"
                echo "  - 포트 충돌 확인: lsof -i :5902"
                ;;
            "IDEMPOTENCY REPLAY OK")
                echo "[IDEMPOTENCY REPLAY OK 누락]"
                echo "  - 멱등키 재시도 테스트 실패"
                echo "  - 확인: server/mw/idempotency.js 구현 확인"
                echo "  - DB 테이블 확인: idempotency_keys 테이블 존재 여부"
                ;;
            "OPENAPI SPEC OK"|"SWAGGER UI OK")
                echo "[OpenAPI/Swagger UI 누락]"
                echo "  - /openapi.yaml 또는 /docs 접근 실패"
                echo "  - 확인: server/app.js에서 r4 오버레이 블록 위치"
                echo "  - 수동 확인: curl http://localhost:5902/openapi.yaml"
                ;;
            "OUTBOX PEEK OK"|"OUTBOX FLUSH OK")
                echo "[Outbox API 누락]"
                echo "  - /admin/outbox/peek 또는 /flush 실패"
                echo "  - 확인: ADMIN_KEY 환경변수 설정"
                echo "  - 확인: server/lib/outbox.js 구현"
                ;;
            "HOUSEKEEPING OK"|"TTL CLEANUP VERIFIED")
                echo "[Housekeeping 누락]"
                echo "  - r5 패치가 적용되지 않았을 수 있습니다."
                echo "  - 확인: scripts/apply_p2_r5.sh 실행 여부"
                echo "  - 확인: server/routes/admin/housekeeping.js 존재 여부"
                ;;
            "DLQ API OK")
                echo "[DLQ API 누락]"
                echo "  - r5 DLQ 기능이 동작하지 않습니다."
                echo "  - 확인: server/routes/admin/housekeeping.js의 DLQ 라우트"
                ;;
        esac
        echo ""
    done
    
    exit 1
else
    echo ""
    echo "✅ 모든 체크포인트 통과!"
fi

echo ""
echo "=== LOG HINT ==="
echo "실시간 서버 로그: tail -f $SERVER_LOG"
echo "Outbox 로그:       tail -f .outbox.log"
echo "실행 로그:         tail -f $LOG_FILE"


