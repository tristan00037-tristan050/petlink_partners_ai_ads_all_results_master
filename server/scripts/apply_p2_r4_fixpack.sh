#!/usr/bin/env bash

set -euo pipefail

echo "[r4-fix] admin middleware: require('./mw/admin') -> require('./mw/admin').requireAdmin"

# Linux (GNU sed)
if sed --version 2>/dev/null | grep -q 'GNU'; then
  sed -i "s/require('\.\/mw\/admin'),/require('\.\/mw\/admin').requireAdmin,/g" server/app.js
# macOS (BSD sed)
else
  sed -i.bak "s/require('\.\/mw\/admin'),/require('\.\/mw\/admin').requireAdmin,/g" server/app.js
  rm -f server/app.js.bak
fi

echo "[r4-fix] done."
