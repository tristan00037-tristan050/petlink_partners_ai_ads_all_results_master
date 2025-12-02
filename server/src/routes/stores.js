const express = require('express');
const { pool } = require('../lib/db');
const { requireAuth } = require('../mw/authn');
const { assertCreateStore, assertSubscribe } = require('../schema/store');

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

/** 매장 생성 */
router.post('/', requireAuth, async (req, res, next) => {
  try {
    const { name, address, phone } = assertCreateStore(req.body);
    const { sub: ownerId, tenant } = req.user;
    const q = `
      INSERT INTO stores (owner_user_id, tenant, name, address, phone)
      VALUES ($1,$2,$3,$4,$5)
      RETURNING id, name, tenant, status, created_at
    `;
    const { rows } = await pool.query(q, [ownerId, tenant, name, address, phone]);
    const store = rows[0];
    // owner 멤버십 보장
    await pool.query(
      `INSERT INTO store_members (store_id, user_id, role)
       VALUES ($1,$2,'owner') ON CONFLICT DO NOTHING`,
      [store.id, ownerId]
    );
    res.json({ ok: true, store });
  } catch (err) { next(err); }
});

/** 내 매장 목록 */
router.get('/', requireAuth, async (req, res, next) => {
  try {
    const { sub: ownerId, tenant } = req.user;
    const { rows } = await pool.query(
      'SELECT id, name, status, created_at FROM stores WHERE owner_user_id=$1 AND tenant=$2 ORDER BY id DESC',
      [ownerId, tenant]
    );
    res.json({ ok: true, items: rows });
  } catch (err) { next(err); }
});

/** 구독 생성(요금제 선택) */
router.post('/stores/:id/subscribe', requireAuth, async (req, res, next) => {
  try {
    const storeId = parseInt(req.params.id, 10);
    const { plan_code } = assertSubscribe(req.body);
    const { sub: ownerId, tenant } = req.user;

    // 멤버십 검증
    if (!(await ensureMember(storeId, req.user))) return res.status(404).json({ ok: false, code: 'NOT_FOUND', message: '매장을 찾을 수 없습니다.' });

    // 플랜 존재 확인 (is_active 컬럼이 없으면 제거)
    const p = await pool.query('SELECT code FROM plans WHERE code=$1', [plan_code]);
    if (!p.rows.length) return res.status(400).json({ ok: false, code: 'INVALID_PLAN' });

    // 활성 구독 중복 방지(기간 내 active 존재 여부)
    const active = await pool.query(
      `SELECT id FROM store_plan_subscriptions
       WHERE store_id=$1 AND status='active' AND now() BETWEEN period_start AND period_end`,
      [storeId]
    );
    if (active.rows.length) {
      return res.json({ ok: true, created: false, reason: 'active_exists' });
    }

    const cycle = parseInt(process.env.BILLING_CYCLE_DAYS || '30', 10);
    const ins = await pool.query(
      `INSERT INTO store_plan_subscriptions (store_id, plan_code, status, period_start, period_end, auto_renew)
       VALUES ($1,$2,'active', now(), now() + ($3 || ' day')::interval, TRUE)
       RETURNING id, plan_code, status, period_start, period_end`,
      [storeId, plan_code, String(cycle)]
    );
    res.json({ ok: true, created: true, subscription: ins.rows[0] });
  } catch (err) { next(err); }
});

module.exports = router;

