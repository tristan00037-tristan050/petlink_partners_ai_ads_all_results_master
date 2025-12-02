const express = require('express');
const { pool } = require('../lib/db');
const { requireAuth } = require('../mw/authn');
const { assertCreateCampaign } = require('../schema/campaign');
const { evaluateText, recordViolations, blockOnBanned } = require('../lib/policy');
const { hasOverdueInvoices } = require('../lib/billing');

const router = express.Router();

async function ensureMember(storeId, user) {
  const q = `
    SELECT 1 FROM stores s
    LEFT JOIN store_members m ON m.store_id=s.id AND m.user_id=$2 AND m.role IN ('owner','manager')
    WHERE s.id=$1 AND s.tenant=$3 AND (s.owner_user_id=$2 OR m.user_id=$2)
    LIMIT 1`;
  const { rows } = await pool.query(q, [storeId, user.sub, user.tenant]);
  return rows.length > 0;
}

async function pushHistory(campaignId, fromStatus, toStatus, reason, note) {
  await pool.query(
    `INSERT INTO campaign_status_history(campaign_id, from_status, to_status, reason_code, note)
     VALUES ($1,$2,$3,$4,$5)`,
    [campaignId, fromStatus || null, toStatus, reason || null, note || null]
  );
}

/** 생성(+ 정책 평가 기록) */
router.post('/stores/:id/campaigns', requireAuth, async (req, res, next) => {
  try {
    const storeId = parseInt(req.params.id, 10);
    if (!(await ensureMember(storeId, req.user))) return res.status(404).json({ ok:false, code:'NOT_FOUND' });

    const { name, objective, daily_budget_krw, primary_text, start_date, end_date } = assertCreateCampaign(req.body);
    const ins = await pool.query(
      `INSERT INTO campaigns (store_id, name, objective, daily_budget_krw, start_date, end_date, primary_text, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,'draft')
       RETURNING id, name, status, created_at`,
      [storeId, name, objective, daily_budget_krw, start_date, end_date, primary_text]
    );
    const campaign = ins.rows[0];

    const evalRes = await evaluateText('primary_text', primary_text);
    await recordViolations('campaign', campaign.id, evalRes.hits);
    await pushHistory(campaign.id, null, 'draft', 'created', `ai_score=${evalRes.ai_score}`);

    res.json({ ok: true, campaign, policy: { violations: evalRes.hits, ai_score: evalRes.ai_score, would_block: evalRes.block } });
  } catch (err) { next(err); }
});

/** 목록 */
router.get('/stores/:id/campaigns', requireAuth, async (req, res, next) => {
  try {
    const storeId = parseInt(req.params.id, 10);
    if (!(await ensureMember(storeId, req.user))) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    const { rows } = await pool.query(
      `SELECT id, name, objective, daily_budget_krw, status, created_at
       FROM campaigns WHERE store_id=$1 ORDER BY id DESC`, [storeId]
    );
    res.json({ ok: true, items: rows });
  } catch (err) { next(err); }
});

/** 활성화(정책·빌링 차단 반영) */
router.post('/campaigns/:cid/activate', requireAuth, async (req, res, next) => {
  try {
    const cid = parseInt(req.params.cid, 10);
    const q = `SELECT c.id, c.store_id, c.status,
                      EXISTS (SELECT 1 FROM policy_violations pv WHERE pv.entity_type='campaign' AND pv.entity_id=c.id AND pv.resolved_at IS NULL) AS has_policy
               FROM campaigns c WHERE c.id=$1`;
    const { rows } = await pool.query(q, [cid]);
    if (!rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    const c = rows[0];
    if (!(await ensureMember(c.store_id, req.user))) return res.status(404).json({ ok:false, code:'NOT_FOUND' });

    if (c.has_policy && blockOnBanned) {
      await pushHistory(c.id, c.status, 'paused', 'blocked_by_policy', 'unresolved policy violation');
      await pool.query(`UPDATE campaigns SET status='paused' WHERE id=$1`, [c.id]);
      return res.status(409).json({ ok:false, code:'BLOCKED_BY_POLICY' });
    }
    if (await hasOverdueInvoices(c.store_id)) {
      await pushHistory(c.id, c.status, 'paused', 'blocked_by_billing', 'overdue invoices');
      await pool.query(`UPDATE campaigns SET status='paused' WHERE id=$1`, [c.id]);
      return res.status(409).json({ ok:false, code:'BLOCKED_BY_BILLING' });
    }

    await pushHistory(c.id, c.status, 'active', 'manual', null);
    await pool.query(`UPDATE campaigns SET status='active' WHERE id=$1`, [c.id]);
    res.json({ ok:true, id:c.id, status:'active' });
  } catch (e) { next(e); }
});

/** 일시중지 */
router.post('/campaigns/:cid/pause', requireAuth, async (req, res, next) => {
  try {
    const cid = parseInt(req.params.cid, 10);
    const { rows } = await pool.query(`SELECT id, store_id, status FROM campaigns WHERE id=$1`, [cid]);
    if (!rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    const c = rows[0];
    if (!(await ensureMember(c.store_id, req.user))) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    await pushHistory(c.id, c.status, 'paused', 'manual', null);
    await pool.query(`UPDATE campaigns SET status='paused' WHERE id=$1`, [c.id]);
    res.json({ ok:true, id:c.id, status:'paused' });
  } catch (e) { next(e); }
});

/** 중지(종료) */
router.post('/campaigns/:cid/stop', requireAuth, async (req, res, next) => {
  try {
    const cid = parseInt(req.params.cid, 10);
    const { rows } = await pool.query(`SELECT id, store_id, status FROM campaigns WHERE id=$1`, [cid]);
    if (!rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    const c = rows[0];
    if (!(await ensureMember(c.store_id, req.user))) return res.status(404).json({ ok:false, code:'NOT_FOUND' });
    await pushHistory(c.id, c.status, 'stopped', 'manual', null);
    await pool.query(`UPDATE campaigns SET status='stopped' WHERE id=$1`, [c.id]);
    res.json({ ok:true, id:c.id, status:'stopped' });
  } catch (e) { next(e); }
});

module.exports = router;
