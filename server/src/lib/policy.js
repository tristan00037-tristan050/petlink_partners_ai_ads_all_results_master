const { pool } = require('./db');
const { scoreText } = require('./policy_ai_stub');
const { callPolicyAI } = require('./policy_ai_client');

const banned = (process.env.POLICY_BANNED_WORDS || '')
  .split(',').map(s => s.trim()).filter(Boolean).map(s => s.toLowerCase());
const blockOnBanned = String(process.env.POLICY_BLOCK_ON_BANNED || 'true') === 'true';
const aiBlockThresh = parseFloat(process.env.POLICY_AI_BLOCK_THRESHOLD || '0.75');

function ruleCheck(field, text) {
  const hits = [];
  if (!text) return hits;
  const lower = String(text).toLowerCase();
  for (const w of banned) if (w && lower.includes(w)) hits.push({ field, rule: 'banned_word', snippet: w });
  return hits;
}

async function evaluateText(field, text) {
  const hits = ruleCheck(field, text);
  // 로컬 stub
  let ai_score = scoreText(text);

  // 외부 AI 플러그인(있으면 우선)
  const aiResp = await callPolicyAI(text);
  if (aiResp.ok && typeof aiResp.score === 'number') ai_score = aiResp.score;

  return { hits, ai_score, block: (blockOnBanned && hits.length > 0) || (ai_score >= aiBlockThresh) };
}

async function recordViolations(entityType, entityId, violations) {
  if (!violations || !violations.length) return;
  const q = 'INSERT INTO policy_violations(entity_type, entity_id, field, rule, snippet) VALUES ($1,$2,$3,$4,$5)';
  for (const v of violations) {
    await pool.query(q, [entityType, entityId, v.field, v.rule, v.snippet || null]);
  }
}

async function resolveViolations(entityType, entityId, note) {
  await pool.query(
    `UPDATE policy_violations SET resolved_at=now()
     WHERE entity_type=$1 AND entity_id=$2 AND resolved_at IS NULL`,
    [entityType, entityId]
  );
  // 기록용 메모는 status history에 남깁니다(관리자 해제 시)
  return true;
}

module.exports = { evaluateText, recordViolations, resolveViolations, ruleCheck, blockOnBanned };
