const express = require('express');
const { pool } = require('../lib/db');
const { requireAdmin } = require('../mw/admin');
const { resolveViolations } = require('../lib/policy');

const router = express.Router();

/** 정책 위반 해제(관리자 승인) */
router.post('/admin/policy/campaigns/:cid/resolve', requireAdmin, async (req, res, next) => {
  try {
    const cid = parseInt(req.params.cid, 10);
    const note = (req.body && req.body.note) || 'admin_resolve';
    const actor = req.header('X-Admin-Actor') || 'unknown';
    const { rows } = await pool.query(`SELECT id, status FROM campaigns WHERE id=$1`, [cid]);
    if (!rows.length) return res.status(404).json({ ok:false, code:'NOT_FOUND' });

    // 미해결 위반들 해제 + 감사 필드 기록
    await pool.query(
      `UPDATE policy_violations
       SET resolved_at=now(), resolved_by=$1, resolved_note=$2
       WHERE entity_type='campaign' AND entity_id=$3 AND resolved_at IS NULL`,
      [actor, note, cid]
    );

    await pool.query(
      `INSERT INTO campaign_status_history(campaign_id, from_status, to_status, reason_code, note)
       VALUES ($1, $2, $2, 'policy_resolved', $3)`,
      [cid, rows[0].status, `${note} by ${actor}`]
    );

    res.json({ ok:true, resolved:true, actor, note });
  } catch (e) { next(e); }
});

/** 빌링 스케줄러 즉시 실행(재현용) */
router.post('/admin/ops/scheduler/run', requireAdmin, async (_req, res, next) => {
  try {
    const { runOnce } = require('../jobs/billing_scheduler');
    await runOnce();
    res.json({ ok:true, triggered:true });
  } catch (e) { next(e); }
});

module.exports = router;

