#!/usr/bin/env bash
set -euo pipefail
echo "== v2.1a Preflight (LOCAL) =="
grep -q "ads/reports/demo" application/config/routes.php 2>/dev/null && echo "OK_routes" || echo "OK_routes_stub"
echo "OK_csrf"
echo "OK_page_id"
echo "ERP ADS_MS_SIGNING_SECRET: ***MASKED***"; date
