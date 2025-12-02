// 간단 점수화 스텁: 금칙어 존재 시 점수↑, 길이/반복/특수문자 비중 등 가중치
function scoreText(text='') {
  const s = String(text || '');
  if (!s) return 0.0;
  let score = 0;
  const lower = s.toLowerCase();
  const banned = (process.env.POLICY_BANNED_WORDS || '').split(',').map(v=>v.trim().toLowerCase()).filter(Boolean);
  for (const w of banned) if (w && lower.includes(w)) score += 0.5;
  const specials = (s.match(/[^a-zA-Z0-9가-힣\s]/g) || []).length;
  if (specials > 5) score += 0.1;
  if (s.length > 120) score += 0.1;
  return Math.min(1, score);
}

module.exports = { scoreText };

