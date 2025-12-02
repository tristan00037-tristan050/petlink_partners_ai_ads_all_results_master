#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://localhost:3001}"
curl -s "${BASE}/healthz"; echo
curl -s -X POST "${BASE}/content/lint" -H "Content-Type: application/json" -d '{"caption":"오늘도 귀여운 산책 🐾"}'; echo
curl -s -X POST "${BASE}/content/lint" -H "Content-Type: application/json" -d '{"caption":"분양/판매/가격 문의"}'; echo
curl -s -X POST "${BASE}/instagram/publish" -H "Content-Type: application/json" -d '{"ig_user_id":"1784","media_type":"IMAGE","media_urls":["https://picsum.photos/seed/dog/800/600"],"caption":"테스트"}'; echo
curl -s "${BASE}/instagram/insights?media_id=123"; echo
