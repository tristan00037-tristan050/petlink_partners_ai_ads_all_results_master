/**
 * P0: Plans API Routes
 * GET /plans, GET /stores/me/plan, POST /stores/me/plan
 */

const express = require('express');
const db = require('../lib/db');
const { appCORS } = require('../mw/cors_split');
const { requireAuth } = require('../mw/auth');

const router = express.Router();

/**
 * GET /plans - 요금제 목록 조회
 */
router.get('/plans', appCORS, async (req, res) => {
  try {
    const plans = await db.q('SELECT * FROM plans ORDER BY price ASC');

    res.json({
      ok: true,
      plans: plans.rows.map(plan => ({
        id: plan.id,
        code: plan.code,
        name: plan.name,
        price: plan.price,
        ad_budget: plan.ad_budget,
        features: plan.features || []
      }))
    });
  } catch (error) {
    console.error('Plans list error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '요금제 목록 조회 중 오류가 발생했습니다.'
    });
  }
});

/**
 * GET /stores/me/plan - 내 요금제 조회
 */
router.get('/stores/me/plan', appCORS, requireAuth, async (req, res) => {
  const userId = req.user?.userId || req.user?.id;

  try {
    const store = await db.q('SELECT id FROM stores WHERE user_id = $1', [userId]);

    if (store.rows.length === 0) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '매장 정보가 없습니다.'
      });
    }

    const subscription = await db.q(
      'SELECT * FROM store_plan_subscriptions WHERE store_id = $1',
      [store.rows[0].id]
    );

    if (subscription.rows.length === 0) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '요금제가 선택되지 않았습니다.'
      });
    }

    res.json({
      ok: true,
      subscription: subscription.rows[0]
    });
  } catch (error) {
    console.error('Subscription get error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '요금제 조회 중 오류가 발생했습니다.'
    });
  }
});

/**
 * POST /stores/me/plan - 요금제 선택/변경
 */
router.post('/stores/me/plan', appCORS, requireAuth, express.json(), async (req, res) => {
  const userId = req.user?.userId || req.user?.id;
  const { plan_id } = req.body;

  if (!plan_id) {
    return res.status(400).json({
      ok: false,
      code: 'INVALID_INPUT',
      message: 'plan_id는 필수입니다.'
    });
  }

  try {
    // 매장 조회
    const store = await db.q('SELECT id FROM stores WHERE user_id = $1', [userId]);

    if (store.rows.length === 0) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '매장 정보가 없습니다.'
      });
    }

    const storeId = store.rows[0].id;

    // 플랜 확인
    const plan = await db.q('SELECT * FROM plans WHERE id = $1', [plan_id]);
    if (plan.rows.length === 0) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '요금제를 찾을 수 없습니다.'
      });
    }

    // 구독 기간 계산 (이번 달 1일 ~ 다음 달 말일)
    const today = new Date();
    const cycleStart = new Date(today.getFullYear(), today.getMonth(), 1);
    const cycleEnd = new Date(today.getFullYear(), today.getMonth() + 1, 0);
    const nextBillingDate = new Date(today.getFullYear(), today.getMonth() + 1, 1);

    // 구독 생성 또는 업데이트
    const existing = await db.q(
      'SELECT id FROM store_plan_subscriptions WHERE store_id = $1',
      [storeId]
    );

    let subscription;
    if (existing.rows.length > 0) {
      // 업데이트
      subscription = await db.q(`
        UPDATE store_plan_subscriptions 
        SET plan_id = $1, status = 'ACTIVE', cycle_start = $2, cycle_end = $3, 
            next_billing_date = $4, updated_at = now()
        WHERE store_id = $5
        RETURNING *
      `, [plan_id, cycleStart, cycleEnd, nextBillingDate, storeId]);
    } else {
      // 생성
      subscription = await db.q(`
        INSERT INTO store_plan_subscriptions (store_id, plan_id, status, cycle_start, cycle_end, next_billing_date)
        VALUES ($1, $2, 'ACTIVE', $3, $4, $5)
        RETURNING *
      `, [storeId, plan_id, cycleStart, cycleEnd, nextBillingDate]);
    }

    res.json({
      ok: true,
      subscription: subscription.rows[0]
    });
  } catch (error) {
    console.error('Subscription create error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '요금제 선택 중 오류가 발생했습니다.'
    });
  }
});

module.exports = router;

