#!/bin/bash
# smoke_p0_blockers.sh - P0 블로커 스모크 테스트

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:5902}"

echo "=== P0 블로커 스모크 테스트 ==="
echo ""

# A. 인증/권한
echo "A. 인증/권한 테스트..."
echo "   POST ${BASE_URL}/auth/signup"
TOK_RESP=$(curl -s -XPOST "${BASE_URL}/auth/signup")
TOK=$(echo "$TOK_RESP" | grep -o '"token":"[^"]*"' | cut -d'"' -f4 || echo "")

if [ -z "$TOK" ]; then
    echo "   ❌ 토큰 발급 실패"
    echo "$TOK_RESP"
    exit 1
fi

STORE_ID=$(echo "$TOK_RESP" | grep -o '"store_id":[0-9]*' | grep -o '[0-9]*' || echo "1")
echo "   ✅ 토큰 발급 성공 (store_id: ${STORE_ID})"

echo "   GET ${BASE_URL}/health (공개 엔드포인트)"
health_resp=$(curl -s "${BASE_URL}/health")
if echo "$health_resp" | grep -q '"ok":true'; then
    echo "   ✅ 공개 엔드포인트 접근 성공"
else
    echo "   ❌ 공개 엔드포인트 접근 실패"
    exit 1
fi

echo "   GET ${BASE_URL}/stores/${STORE_ID}/channel-prefs (인증 없음)"
unauth_resp=$(curl -s "${BASE_URL}/stores/${STORE_ID}/channel-prefs")
if echo "$unauth_resp" | grep -q '"error":"UNAUTHORIZED"'; then
    echo "   ✅ 인증 없이 접근 차단 성공"
else
    echo "   ⚠️ 인증 없이 접근 차단 실패 (계속 진행)"
fi

echo "   GET ${BASE_URL}/stores/${STORE_ID}/channel-prefs (인증 있음)"
auth_resp=$(curl -s -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: ${STORE_ID}" "${BASE_URL}/stores/${STORE_ID}/channel-prefs")
if echo "$auth_resp" | grep -q '"ig_enabled"'; then
    echo "   ✅ 인증 후 접근 성공"
else
    echo "   ❌ 인증 후 접근 실패"
    exit 1
fi

echo "   GET ${BASE_URL}/stores/${STORE_ID}/channel-prefs (다른 store_id)"
wrong_resp=$(curl -s -H "Authorization: Bearer ${TOK}" -H "X-Store-ID: 999" "${BASE_URL}/stores/${STORE_ID}/channel-prefs")
if echo "$wrong_resp" | grep -q '"error":"FORBIDDEN"'; then
    echo "   ✅ 다른 store_id 접근 차단 성공"
else
    echo "   ⚠️ 다른 store_id 접근 차단 실패 (계속 진행)"
fi

echo ""

# B. 정책/카피 필터
echo "B. 정책/카피 필터 테스트..."
echo "   POST ${BASE_URL}/animals (금지어 포함)"
policy_resp=$(curl -s -XPOST "${BASE_URL}/animals" \
    -H "Authorization: Bearer ${TOK}" \
    -H "X-Store-ID: ${STORE_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"store_id\":${STORE_ID},\"species\":\"dog\",\"note\":\"가격 특가 즉시분양\"}")

if echo "$policy_resp" | grep -q '"code":"POLICY_TEXT_VIOLATION"'; then
    echo "   ✅ 금지어 차단 성공"
else
    echo "   ⚠️ 금지어 차단 실패 (계속 진행)"
fi

echo ""

# C. 초안 발행·승인토큰
echo "C. 초안 발행·승인토큰 테스트..."
echo "   POST ${BASE_URL}/organic/drafts"
draft_resp=$(curl -s -XPOST "${BASE_URL}/organic/drafts" \
    -H "Authorization: Bearer ${TOK}" \
    -H "X-Store-ID: ${STORE_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"store_id\":${STORE_ID},\"copy\":\"상담/방문 안내\",\"channels\":[\"META\",\"YOUTUBE\"]}")

DRAFT_ID=$(echo "$draft_resp" | grep -o '"draft_id":[0-9]*' | grep -o '[0-9]*' || echo "")

if [ -n "$DRAFT_ID" ]; then
    echo "   ✅ 초안 생성 성공 (draft_id: ${DRAFT_ID})"
    
    echo "   POST ${BASE_URL}/organic/drafts/${DRAFT_ID}/publish"
    publish_resp=$(curl -s -XPOST "${BASE_URL}/organic/drafts/${DRAFT_ID}/publish" \
        -H "Authorization: Bearer ${TOK}" \
        -H "X-Store-ID: ${STORE_ID}")
    
    if echo "$publish_resp" | grep -q '"status":"PARTIAL"\|"status":"PUBLISHED"'; then
        echo "   ✅ 초안 발행 성공"
        if echo "$publish_resp" | grep -q '"approve_token"'; then
            echo "   ✅ 승인 토큰 발급 확인"
        fi
    else
        echo "   ⚠️ 초안 발행 실패 (계속 진행)"
    fi
else
    echo "   ⚠️ 초안 생성 실패 (계속 진행)"
fi

echo ""

# D. 인게스트·일일 페이싱 강제
echo "D. 인게스트·일일 페이싱 강제 테스트..."
echo "   POST ${BASE_URL}/pacer/preview"
TODAY_MONTH=$(date -u +%Y-%m)
pacer_preview_resp=$(curl -s -XPOST "${BASE_URL}/pacer/preview" \
    -H "Authorization: Bearer ${TOK}" \
    -H "X-Store-ID: ${STORE_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"store_id\":${STORE_ID},\"month\":\"${TODAY_MONTH}\",\"remaining_budget\":10000}")

if echo "$pacer_preview_resp" | grep -q '"schedule"'; then
    echo "   ✅ Pacer 프리뷰 성공"
    
    SCHEDULE_JSON=$(echo "$pacer_preview_resp" | grep -o '"schedule":\[[^]]*\]' || echo "")
    if [ -n "$SCHEDULE_JSON" ]; then
        TODAY_DATE=$(date -u +%Y-%m-%d)
        TODAY_AMOUNT=$(echo "$pacer_preview_resp" | grep -o "\"date\":\"${TODAY_DATE}\"[^}]*" | grep -o '"amount":[0-9]*' | grep -o '[0-9]*' | head -1 || echo "1000")
        TODAY_MAX=$(echo "$pacer_preview_resp" | grep -o "\"date\":\"${TODAY_DATE}\"[^}]*" | grep -o '"max":[0-9]*' | grep -o '[0-9]*' | head -1 || echo "1200")
        
        echo "   POST ${BASE_URL}/pacer/apply"
        pacer_apply_resp=$(curl -s -XPOST "${BASE_URL}/pacer/apply" \
            -H "Authorization: Bearer ${TOK}" \
            -H "X-Store-ID: ${STORE_ID}" \
            -H "Content-Type: application/json" \
            -d "{\"store_id\":${STORE_ID},\"month\":\"${TODAY_MONTH}\",\"schedule\":[{\"date\":\"${TODAY_DATE}\",\"amount\":${TODAY_AMOUNT},\"min\":800,\"max\":${TODAY_MAX}}]}")
        
        if echo "$pacer_apply_resp" | grep -q '"ok":true'; then
            echo "   ✅ Pacer 적용 성공"
            
            # 인게스트로 지출 누적
            echo "   POST ${BASE_URL}/ingest/META"
            ingest_resp=$(curl -s -XPOST "${BASE_URL}/ingest/META" \
                -H "Authorization: Bearer ${TOK}" \
                -H "X-Store-ID: ${STORE_ID}" \
                -H "Content-Type: application/json" \
                -d "[{\"ts\":\"$(date -u +%FT%TZ)\",\"store_id\":${STORE_ID},\"cost\":1300}]")
            
            if echo "$ingest_resp" | grep -q '"ok":true'; then
                echo "   ✅ 인게스트 성공"
                
                # 상한 초과 시 발행 차단 확인
                if [ "$TODAY_MAX" -lt 1300 ]; then
                    echo "   POST ${BASE_URL}/organic/drafts/${DRAFT_ID}/publish (상한 초과 시도)"
                    cap_resp=$(curl -s -XPOST "${BASE_URL}/organic/drafts/${DRAFT_ID}/publish" \
                        -H "Authorization: Bearer ${TOK}" \
                        -H "X-Store-ID: ${STORE_ID}")
                    
                    if echo "$cap_resp" | grep -q '"error":"DAILY_CAP_REACHED"'; then
                        echo "   ✅ 일일 상한 초과 차단 성공"
                    else
                        echo "   ⚠️ 일일 상한 초과 차단 실패 (계속 진행)"
                    fi
                fi
            else
                echo "   ⚠️ 인게스트 실패 (계속 진행)"
            fi
        else
            echo "   ⚠️ Pacer 적용 실패 (계속 진행)"
        fi
    fi
else
    echo "   ⚠️ Pacer 프리뷰 실패 (계속 진행)"
fi

echo ""

# E. FFmpeg 가용성
echo "E. FFmpeg 가용성 체크..."
if command -v ffmpeg >/dev/null 2>&1; then
    echo "   ✅ FFmpeg 설치됨"
else
    echo "   ⚠️ FFmpeg 미설치 (동영상 처리 시 FFMPEG_NOT_FOUND 반환 예상)"
fi

echo ""

# F. CORS/보안 헤더
echo "F. CORS/보안 헤더 테스트..."
echo "   OPTIONS ${BASE_URL}/health (CORS preflight)"
cors_resp=$(curl -s -XOPTIONS "${BASE_URL}/health" \
    -H "Origin: http://localhost:8000" \
    -H "Access-Control-Request-Method: GET" \
    -i)

if echo "$cors_resp" | grep -qi "access-control-allow-origin"; then
    echo "   ✅ CORS 헤더 확인"
else
    echo "   ⚠️ CORS 헤더 확인 실패 (계속 진행)"
fi

echo "   GET ${BASE_URL}/health (보안 헤더 확인)"
security_resp=$(curl -s -I "${BASE_URL}/health")

if echo "$security_resp" | grep -qi "x-content-type-options\|x-frame-options"; then
    echo "   ✅ 보안 헤더 확인 (Helmet)"
else
    echo "   ⚠️ 보안 헤더 확인 실패 (계속 진행)"
fi

echo ""
echo "=== 모든 테스트 완료 ==="


