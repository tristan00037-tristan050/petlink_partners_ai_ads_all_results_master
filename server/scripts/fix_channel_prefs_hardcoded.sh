#!/bin/bash
# channel_prefs.html 하드코딩 제거 스크립트

FILE="web/pages/channel_prefs.html"

# 백업 확인
if [ ! -f "${FILE}.bak" ]; then
    cp "$FILE" "${FILE}.bak"
    echo "✅ 백업 생성: ${FILE}.bak"
fi

# 색상 치환
sed -i '' -E "s/color:\s*#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})/color: var(--color-fg)/g" "$FILE"
sed -i '' -E "s/color:\s*#111/color: var(--color-fg)/g" "$FILE"
sed -i '' -E "s/color:\s*#333/color: var(--color-fg)/g" "$FILE"
sed -i '' -E "s/color:\s*#666/color: var(--color-fg)/g" "$FILE"
sed -i '' -E "s/color:\s*#fff/color: #fff/g" "$FILE"  # 흰색은 유지

# 배경색 치환
sed -i '' -E "s/background:\s*#fff/background: var(--color-bg)/g" "$FILE"
sed -i '' -E "s/background:\s*#f9fafb/background: var(--color-muted)/g" "$FILE"
sed -i '' -E "s/background:\s*#f3f4f6/background: var(--color-muted)/g" "$FILE"

# 테두리 치환
sed -i '' -E "s/border:\s*([0-9]+px\s+)?solid\s*#e5e7eb/border: 1px solid var(--color-border)/g" "$FILE"
sed -i '' -E "s/border:\s*2px\s+solid\s*#e5e7eb/border: 2px solid var(--color-border)/g" "$FILE"
sed -i '' -E "s/border-color:\s*#e5e7eb/border-color: var(--color-border)/g" "$FILE"
sed -i '' -E "s/border-color:\s*#667eea/border-color: var(--color-primary)/g" "$FILE"

# 라운드 치환
sed -i '' -E "s/border-radius:\s*12px/border-radius: var(--radius-sm)/g" "$FILE"
sed -i '' -E "s/border-radius:\s*16px/border-radius: var(--radius)/g" "$FILE"
sed -i '' -E "s/border-radius:\s*8px/border-radius: var(--radius-sm)/g" "$FILE"

# 폰트 치환
sed -i '' -E "s/font-family:\s*[^;]+/font-family: var(--font-sans)/g" "$FILE"

# 폰트 사이즈 치환
sed -i '' -E "s/font-size:\s*14px/font-size: var(--fs-sm)/g" "$FILE"
sed -i '' -E "s/font-size:\s*16px/font-size: var(--fs-base)/g" "$FILE"
sed -i '' -E "s/font-size:\s*18px/font-size: var(--fs-lg)/g" "$FILE"
sed -i '' -E "s/font-size:\s*20px/font-size: var(--fs-lg)/g" "$FILE"
sed -i '' -E "s/font-size:\s*24px/font-size: var(--fs-xl)/g" "$FILE"
sed -i '' -E "s/font-size:\s*28px/font-size: var(--fs-2xl)/g" "$FILE"
sed -i '' -E "s/font-size:\s*36px/font-size: var(--fs-2xl)/g" "$FILE"

# 간격 치환
sed -i '' -E "s/padding:\s*8px/padding: var(--space-1)/g" "$FILE"
sed -i '' -E "s/padding:\s*12px/padding: var(--space-2)/g" "$FILE"
sed -i '' -E "s/padding:\s*16px/padding: var(--space-3)/g" "$FILE"
sed -i '' -E "s/padding:\s*20px/padding: var(--space-3)/g" "$FILE"
sed -i '' -E "s/padding:\s*24px/padding: var(--space-4)/g" "$FILE"
sed -i '' -E "s/padding:\s*30px/padding: var(--space-4)/g" "$FILE"
sed -i '' -E "s/padding:\s*40px/padding: var(--space-4)/g" "$FILE"

sed -i '' -E "s/margin:\s*8px/margin: var(--space-1)/g" "$FILE"
sed -i '' -E "s/margin:\s*12px/margin: var(--space-2)/g" "$FILE"
sed -i '' -E "s/margin:\s*16px/margin: var(--space-3)/g" "$FILE"
sed -i '' -E "s/margin:\s*24px/margin: var(--space-4)/g" "$FILE"
sed -i '' -E "s/margin:\s*30px/margin: var(--space-4)/g" "$FILE"

# 특수 색상 치환
sed -i '' -E "s/#667eea/var(--color-primary)/g" "$FILE"
sed -i '' -E "s/#764ba2/var(--color-accent)/g" "$FILE"
sed -i '' -E "s/rgba\(102,\s*126,\s*234/var(--color-primary)/g" "$FILE"
sed -i '' -E "s/rgba\(118,\s*75,\s*162/var(--color-accent)/g" "$FILE"

echo "✅ 하드코딩 치환 완료: $FILE"
echo "📋 백업: ${FILE}.bak"


