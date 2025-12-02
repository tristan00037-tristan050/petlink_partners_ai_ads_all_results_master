#!/bin/bash
# UI 미리보기 열기 스크립트

cd "$(dirname "$0")"

if [ ! -f "ui_preview_static.zip" ]; then
  echo "❌ ui_preview_static.zip 파일을 찾을 수 없습니다."
  echo "현재 위치: $(pwd)"
  exit 1
fi

# 압축 해제
if [ ! -d "ui_preview_static" ]; then
  unzip -q ui_preview_static.zip
fi

# 브라우저로 열기
if [ -f "ui_preview_static/webapp/index.html" ]; then
  open ui_preview_static/webapp/index.html
  echo "✅ WebApp 미리보기 열림"
fi

if [ -f "ui_preview_static/admin/index.html" ]; then
  open ui_preview_static/admin/index.html
  echo "✅ Admin 미리보기 열림"
fi
