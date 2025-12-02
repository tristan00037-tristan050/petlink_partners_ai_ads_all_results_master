#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export $(grep -v '^#' .env | xargs)
node src/jobs/payment_reprocessor.js

