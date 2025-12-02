#!/usr/bin/env bash
set -euo pipefail
OUT="artifacts/webapp_evidence_$(date +%Y%m%d_%H%M%S).tgz"
TMP="$(mktemp -d)"
PORT="${PORT:-5902}"
ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
# 수집
curl -sf "http://localhost:${PORT}/admin/webapp/gate" -H "X-Admin-Key: ${ADMIN_KEY}" > "${TMP}/gate.json" || true
curl -sf "http://localhost:${PORT}/admin/webapp/loop/stats.json" -H "X-Admin-Key: ${ADMIN_KEY}" > "${TMP}/loop_stats.json" || true
curl -sf "http://localhost:${PORT}/admin/webapp/gate/report" -H "X-Admin-Key: ${ADMIN_KEY}" > "${TMP}/gate_report.json" || true
psql "${DATABASE_URL}" -Atc "select * from channel_rules order by channel, rule_version desc;" > "${TMP}/channel_rules.tsv" || true
psql "${DATABASE_URL}" -Atc "select decision, used_autofix, loop_id, dur_ms, created_at from ad_moderation_logs order by id desc limit 500;" > "${TMP}/moderation_logs.tsv" || true
tar -czf "${OUT}" -C "${TMP}" .
echo "${OUT}"
