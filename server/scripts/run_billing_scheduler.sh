#!/usr/bin/env bash
set -euo pipefail
export $(grep -v '^#' .env | xargs)
node src/jobs/billing_scheduler.js

