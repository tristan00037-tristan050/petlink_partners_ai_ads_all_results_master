function assertCreateCampaign(body) {
  if (!body || typeof body !== 'object') throw new Error('잘못된 요청');
  const name = String(body.name || '').trim();
  const objective = String(body.objective || '').trim(); // 'traffic' | 'leads'
  const daily_budget_krw = Number.isFinite(body.daily_budget_krw) ? parseInt(body.daily_budget_krw,10) : 0;
  const primary_text = body.primary_text ? String(body.primary_text) : '';
  const start_date = body.start_date ? String(body.start_date) : null;
  const end_date = body.end_date ? String(body.end_date) : null;
  if (!name) throw new Error('name 필수');
  if (!objective) throw new Error('objective 필수');
  return { name, objective, daily_budget_krw, primary_text, start_date, end_date };
}

module.exports = { assertCreateCampaign };

