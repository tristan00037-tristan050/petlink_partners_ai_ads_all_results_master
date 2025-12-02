#!/usr/bin/env bash
set -euo pipefail
BASE="${BASE:-http://localhost:5902}"; ADMIN_KEY="${ADMIN_KEY:?}"; HDR=(-H "X-Admin-Key: ${ADMIN_KEY}")

usage(){ echo "Usage: $0 promote <percent> <adv_ids_csv> | backout <adv_ids_csv>"; exit 1; }

act="${1:-}"; shift || true
case "$act" in
  promote)
    pct="${1:?percent}"; shift
    IFS=',' read -r -a aids <<< "${1:?adv_ids_csv}"
    for aid in "${aids[@]}"; do
      curl -sf -XPOST "${BASE}/admin/prod/cutover/apply" "${HDR[@]}" \
        -H "Content-Type: application/json" \
        -d "{\"advertiser_id\":${aid},\"percent\":${pct},\"dryrun\":false}" >/dev/null \
        && echo "PROMOTE OK ${aid} -> ${pct}%" || echo "PROMOTE FAIL ${aid}"
    done
  ;;
  backout)
    IFS=',' read -r -a aids <<< "${1:?adv_ids_csv}"
    for aid in "${aids[@]}"; do
      curl -sf -XPOST "${BASE}/admin/prod/cutover/backout" "${HDR[@]}" \
        -H "Content-Type: application/json" \
        -d "{\"advertiser_id\":${aid},\"fallback_percent\":0,\"dryrun\":false}" >/dev/null \
        && echo "BACKOUT OK ${aid}" || echo "BACKOUT FAIL ${aid}"
    done
  ;;
  *) usage ;;
esac

