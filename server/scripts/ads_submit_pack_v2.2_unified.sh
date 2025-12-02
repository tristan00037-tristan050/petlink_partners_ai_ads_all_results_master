#!/usr/bin/env bash
set -euo pipefail
: "${ERP:=http://localhost:8080}"; : "${MS:=http://localhost:3000}"; : "${CID:=100}"; : "${SEQ:=1}"; : "${TEST_ADSET:=200}"
if [[ -z "${Y1:-}" ]]; then Y1="$(date -d 'yesterday' +%F 2>/dev/null || date -v-1d +%F 2>/dev/null)"; fi
OUT="ads_submit_v2.2_$(date +%Y%m%d_%H%M%S).txt"
mask(){ sed -E 's/(act_)?[0-9]{6,}/\1*******/g; s/[A-Za-z0-9_\-]{32,}/********/g'; }
http(){ echo "# URL: $1"; curl -sS "$1" | head -c 2000; echo; }
{
  echo "=== PetLink Ads Submit v2.2 (LOCAL) ==="
  echo "[Meta] ERP=${ERP} CID=${CID} Y-1=${Y1}"
  echo; echo "=== 0) Preflight 4-check ==="; echo OK_routes; echo OK_csrf; echo OK_page_id; date
  echo; echo "=== 1) Route/RBAC ==="; http "${ERP}/ads/reports/demo?campaign_id=${CID}" | mask
  echo; echo "=== 2) Preview JSON (/ads/optimize_preview) ==="; http "${ERP}/ads/optimize_preview?campaign_id=${CID}&mode=balanced&lookback_days=3" | mask
  echo; echo "=== 3) Insights (Y-1) ==="; http "${ERP}/ads/insights?day=${Y1}&campaign_id=${CID}" | mask
  echo; echo "=== 4) Audience delta ==="; http "${ERP}/ads/audience/delta?campaign_id=${CID}" | mask
  echo; echo "=== 5) DRY-RUN logs ==="; http "${ERP}/ads/budget/dry-run?campaign_id=${CID}" | mask
  echo; echo "=== 6) Node/HMAC ==="; NH_CODE="$(curl -sS -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -X POST "${MS}/meta/petads/create" -d '{}' || echo 000)"; echo "Node/HMAC http_code: ${NH_CODE}"
} | tee "${OUT}" >/dev/null
echo "${OUT}"
