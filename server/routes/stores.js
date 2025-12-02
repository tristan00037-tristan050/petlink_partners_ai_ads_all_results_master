/**
 * P0: Stores API Routes
 * GET/PUT /stores/me - 매장 정보 조회/수정
 */

const express = require('express');
const db = require('../lib/db');
const { appCORS } = require('../mw/cors_split');
const { requireAuth } = require('../mw/auth');

const router = express.Router();

/**
 * GET /stores/me - 내 매장 정보 조회
 */
router.get('/stores/me', appCORS, requireAuth, async (req, res) => {
  const userId = req.user?.id;

  try {
    const store = await db.q(
      'SELECT * FROM stores WHERE user_id = $1',
      [userId]
    );

    if (!store.rows[0]) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '매장 정보가 없습니다.'
      });
    }

    // is_complete 계산 (필수 필드: name, short_description, images(≥1))
    const s = store.rows[0];
    const isComplete = !!(s.name && s.short_description && s.images && s.images.length > 0);

    res.json({
      ok: true,
      store: {
        ...s,
        is_complete: isComplete
      }
    });
  } catch (error) {
    console.error('Store get error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '매장 정보 조회 중 오류가 발생했습니다.'
    });
  }
});

/**
 * PUT /stores/me - 내 매장 정보 수정
 */
router.put('/stores/me', appCORS, requireAuth, express.json(), async (req, res) => {
  const userId = req.user?.id;
  const { name, address, phone, business_hours, short_description, description, images } = req.body;

  // 필수 필드 검증
  if (!name || !short_description) {
    return res.status(400).json({
      ok: false,
      code: 'STORE_PROFILE_INCOMPLETE',
      message: '매장명과 한 줄 소개는 필수입니다.'
    });
  }

  try {
    // 기존 매장 확인
    const existing = await db.q(
      'SELECT id FROM stores WHERE user_id = $1',
      [userId]
    );

    let store;
    if (existing.rows[0]) {
      // 업데이트
      store = await db.q(`
        UPDATE stores 
        SET name = $1, address = $2, phone = $3, business_hours = $4, 
            short_description = $5, description = $6, images = $7, updated_at = now()
        WHERE user_id = $8
        RETURNING *
      `, [name, address || null, phone || null, business_hours || null, 
          short_description, description || null, images || [], userId]);
    } else {
      // 생성
      store = await db.q(`
        INSERT INTO stores (user_id, name, address, phone, business_hours, short_description, description, images)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING *
      `, [userId, name, address || null, phone || null, business_hours || null, 
          short_description, description || null, images || []]);
    }

    // is_complete 계산
    const s = store.rows[0];
    const isComplete = !!(s.name && s.short_description && s.images && s.images.length > 0);

    // is_complete 업데이트
    await db.q('UPDATE stores SET is_complete = $1 WHERE id = $2', [isComplete, s.id]);

    res.json({
      ok: true,
      store: {
        ...s,
        is_complete: isComplete
      }
    });
  } catch (error) {
    console.error('Store update error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '매장 정보 수정 중 오류가 발생했습니다.'
    });
  }
});

module.exports = router;

