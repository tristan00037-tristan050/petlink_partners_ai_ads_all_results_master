/**
 * P0: Admin Stores API Routes
 * GET /admin/stores, PATCH /admin/stores/:id/status
 */

const express = require('express');
const db = require('../lib/db');
const { adminCORS } = require('../mw/cors_split');
const { requireAdmin } = require('../mw/admin_gate');

const router = express.Router();

/**
 * GET /admin/stores - 매장 목록 조회
 */
router.get('/admin/stores', adminCORS, requireAdmin, async (req, res) => {
  const { q, status } = req.query;

  try {
    let query = `
      SELECT 
        s.id,
        s.name,
        s.phone,
        s.is_complete,
        u.email,
        sps.status as subscription_status,
        p.code as plan_code,
        s.created_at
      FROM stores s
      JOIN users u ON s.user_id = u.id
      LEFT JOIN store_plan_subscriptions sps ON s.id = sps.store_id
      LEFT JOIN plans p ON sps.plan_id = p.id
      WHERE 1=1
    `;
    const params = [];
    let paramIndex = 1;

    // 검색어 필터
    if (q) {
      query += ` AND (s.name ILIKE $${paramIndex} OR u.email ILIKE $${paramIndex} OR s.phone ILIKE $${paramIndex})`;
      params.push(`%${q}%`);
      paramIndex++;
    }

    // 상태 필터 (구독 상태 기준)
    if (status) {
      if (status === 'active') {
        query += ` AND sps.status = 'ACTIVE'`;
      } else if (status === 'inactive') {
        query += ` AND (sps.status = 'OVERDUE' OR sps.status = 'CANCELLED')`;
      } else if (status === 'pending') {
        query += ` AND s.is_complete = false`;
      }
    }

    query += ' ORDER BY s.created_at DESC LIMIT 100';

    const stores = await db.q(query, params);

    res.json({
      ok: true,
      stores: stores.rows.map(s => ({
        id: s.id,
        name: s.name,
        email: s.email,
        phone: s.phone,
        plan_code: s.plan_code,
        subscription_status: s.subscription_status,
        store_status: s.subscription_status === 'ACTIVE' ? 'active' : 'inactive',
        created_at: s.created_at
      }))
    });
  } catch (error) {
    console.error('Admin stores list error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '매장 목록 조회 중 오류가 발생했습니다.'
    });
  }
});

/**
 * PATCH /admin/stores/:id/status - 매장 상태 변경
 */
router.patch('/admin/stores/:id/status', adminCORS, requireAdmin, express.json(), async (req, res) => {
  const { id } = req.params;
  const { status } = req.body;

  if (!status || !['active', 'inactive'].includes(status)) {
    return res.status(400).json({
      ok: false,
      code: 'INVALID_STATUS',
      message: '유효하지 않은 상태입니다. (active, inactive)'
    });
  }

  try {
    // 매장 조회
    const store = await db.q('SELECT * FROM stores WHERE id = $1', [id]);

    if (!store.rows[0]) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '매장을 찾을 수 없습니다.'
      });
    }

    // 구독 상태 업데이트
    const subscriptionStatus = status === 'active' ? 'ACTIVE' : 'CANCELLED';
    
    await db.q(`
      UPDATE store_plan_subscriptions 
      SET status = $1, updated_at = now()
      WHERE store_id = $2
    `, [subscriptionStatus, id]);

    // 매장 정보 조회 (응답용)
    const updated = await db.q(`
      SELECT 
        s.id,
        s.name,
        s.phone,
        u.email,
        sps.status as subscription_status,
        p.code as plan_code,
        s.created_at
      FROM stores s
      JOIN users u ON s.user_id = u.id
      LEFT JOIN store_plan_subscriptions sps ON s.id = sps.store_id
      LEFT JOIN plans p ON sps.plan_id = p.id
      WHERE s.id = $1
    `, [id]);

    res.json({
      ok: true,
      store: {
        id: updated.rows[0].id,
        name: updated.rows[0].name,
        email: updated.rows[0].email,
        phone: updated.rows[0].phone,
        plan_code: updated.rows[0].plan_code,
        subscription_status: updated.rows[0].subscription_status,
        store_status: status,
        created_at: updated.rows[0].created_at
      }
    });
  } catch (error) {
    console.error('Admin store status update error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '매장 상태 변경 중 오류가 발생했습니다.'
    });
  }
});

module.exports = router;

