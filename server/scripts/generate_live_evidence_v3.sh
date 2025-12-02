#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-5902}"
ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
STAMP="$(date +%Y%m%d_%H%M%S)"
DIR="evidence/live_proof_v3_${STAMP}"
mkdir -p "${DIR}/api" "${DIR}/db" "${DIR}/openapi" || true

curl -sf "http://localhost:${PORT}/health" > "${DIR}/api/health.json" || true
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/ads/billing/gate/final" > "${DIR}/api/final_check.json" || true
curl -sf -H "X-Admin-Key: ${ADMIN_KEY}" "http://localhost:${PORT}/admin/ads/billing/monitor.json?hours=24" > "${DIR}/api/monitor_24h.json" || true
curl -sf "http://localhost:${PORT}/openapi_ops_live.yaml" > "${DIR}/openapi/ops_live.yaml" || true
curl -sf "http://localhost:${PORT}/openapi_quality.yaml" > "${DIR}/openapi/quality.yaml" || true

psql "${DATABASE_URL}" -c "COPY (SELECT * FROM ad_invoices ORDER BY id DESC LIMIT 200) TO STDOUT WITH CSV HEADER" > "${DIR}/db/ad_invoices.csv" || true
psql "${DATABASE_URL}" -c "COPY (SELECT * FROM ad_payments ORDER BY id DESC LIMIT 200) TO STDOUT WITH CSV HEADER" > "${DIR}/db/ad_payments.csv" || true
psql "${DATABASE_URL}" -c "COPY (SELECT * FROM audit_logs ORDER BY id DESC LIMIT 200) TO STDOUT WITH CSV HEADER" > "${DIR}/db/audit_logs.csv" || true
psql "${DATABASE_URL}" -c "COPY (SELECT id,topic,status,created_at FROM outbox WHERE topic LIKE 'AD_BILLING_%' ORDER BY id DESC LIMIT 500) TO STDOUT WITH CSV HEADER" > "${DIR}/db/outbox_events.csv" || true
tail -n 500 .petlink.out > "${DIR}/petlink_tail.log" || true

tar -czf "${DIR}.tgz" -C evidence "$(basename "${DIR}")"
echo "${DIR}.tgz"
