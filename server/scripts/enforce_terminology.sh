#!/usr/bin/env bash
set -euo pipefail
MODE="${1:---fix}" # --fix | --check
# 대상 확장자(텍스트 위주)
GLOB='*.{md,txt,mdx,js,ts,tsx,jsx,json,yaml,yml}'
# 자동 교정
if [ "$MODE" = "--fix" ]; then
  if command -v git >/dev/null 2>&1 && [ -d .git ]; then
    git ls-files $GLOB 2>/dev/null | xargs -I{} sed -i.bak "s/필요하면/다음단계 개발/g" "{}" 2>/dev/null || true
    find . -name "*.bak" -delete 2>/dev/null || true
  fi
fi
# 검사용
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  HITS=$(git ls-files $GLOB 2>/dev/null | xargs -I{} grep -nH "필요하면" "{}" 2>/dev/null || true)
else
  HITS=""
fi
if [ -n "$HITS" ]; then
  echo "[TERM] 금지 용어 발견"; echo "$HITS"; exit 1
fi
echo "TERM GUARD OK"
