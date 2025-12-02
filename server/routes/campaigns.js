/**
 * P0: Campaigns API Routes
 * POST /campaigns - 캠페인 생성 (STORE_PROFILE_INCOMPLETE 검증 포함)
 */

const express = require('express');
const db = require('../lib/db');
const policyEngine = require('../lib/policy_engine');
const { appCORS } = require('../mw/cors_split');
const { requireAuth } = require('../mw/auth');

const router = express.Router();

/**
 * POST /campaigns - 캠페인 생성
 * 검증: 매장 정보 미완성 시 400 + STORE_PROFILE_INCOMPLETE
 */
router.post('/campaigns', appCORS, requireAuth, express.json(), async (req, res) => {
  const { pet_id, title, body, hashtags, images, videos, channels } = req.body;
  const userId = req.user?.id;

  try {
    // 1. 매장 정보 조회 및 완성도 검증
    const store = await db.q(
      'SELECT id, is_complete FROM stores WHERE user_id = $1',
      [userId]
    );

    if (!store.rows[0]) {
      return res.status(400).json({
        ok: false,
        code: 'STORE_PROFILE_INCOMPLETE',
        message: '매장 정보를 먼저 완성해 주세요.'
      });
    }

    if (!store.rows[0].is_complete) {
      return res.status(400).json({
        ok: false,
        code: 'STORE_PROFILE_INCOMPLETE',
        message: '매장 정보를 먼저 완성해 주세요.'
      });
    }

    // 2. 필수 필드 검증
    if (!pet_id || !title || !body || !channels || channels.length === 0) {
      return res.status(400).json({
        ok: false,
        code: 'INVALID_INPUT',
        message: '필수 필드가 누락되었습니다.'
      });
    }

    // 3. PolicyEngine 검증
    const policyResult = await policyEngine.validate({
      title,
      body,
      hashtags: hashtags || []
    });

    // 4. policy_violations 기록
    let campaignStatus = 'DRAFT';
    if (policyResult.decision === 'REJECT') {
      campaignStatus = 'REJECTED_BY_POLICY';
    } else if (policyResult.decision === 'REVIEW') {
      campaignStatus = 'PENDING_REVIEW';
    } else {
      campaignStatus = 'SUBMITTED';
    }

    // 5. 캠페인 생성
    const campaign = await db.q(`
      INSERT INTO campaigns (store_id, pet_id, title, body, hashtags, images, videos, channels, status)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
      RETURNING *
    `, [
      store.rows[0].id,
      pet_id,
      title,
      body,
      hashtags || [],
      images || [],
      videos || [],
      channels,
      campaignStatus
    ]);

    const campaignId = campaign.rows[0].id;

    // 6. policy_violations 기록
    if (policyResult.reasons.length > 0) {
      for (const reason of policyResult.reasons) {
        await db.q(`
          INSERT INTO policy_violations (campaign_id, type, field, keyword, code, score, message, suggested_body, suggested_hashtags)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        `, [
          campaignId,
          reason.type,
          reason.field,
          reason.keyword || null,
          reason.code || null,
          reason.score || null,
          reason.message,
          policyResult.suggested_body || null,
          policyResult.suggested_hashtags || null
        ]);
      }
    }

    // 7. policy_violations 조회하여 응답에 포함
    const violations = await db.q(
      'SELECT * FROM policy_violations WHERE campaign_id = $1',
      [campaignId]
    );

    res.status(201).json({
      ok: true,
      campaign: {
        ...campaign.rows[0],
        policy_violations: violations.rows
      }
    });

  } catch (error) {
    console.error('Campaign creation error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '캠페인 생성 중 오류가 발생했습니다.'
    });
  }
});

/**
 * GET /campaigns - 캠페인 목록 조회
 */
router.get('/campaigns', appCORS, requireAuth, async (req, res) => {
  const userId = req.user?.id;
  const { status } = req.query;

  try {
    const store = await db.q('SELECT id FROM stores WHERE user_id = $1', [userId]);
    if (!store.rows[0]) {
      return res.json({ ok: true, campaigns: [] });
    }

    let query = 'SELECT * FROM campaigns WHERE store_id = $1';
    const params = [store.rows[0].id];

    if (status) {
      query += ' AND status = $2';
      params.push(status);
    }

    query += ' ORDER BY created_at DESC';

    const campaigns = await db.q(query, params);

    // 각 캠페인의 policy_violations 조회
    const campaignsWithViolations = await Promise.all(
      campaigns.rows.map(async (campaign) => {
        const violations = await db.q(
          'SELECT * FROM policy_violations WHERE campaign_id = $1',
          [campaign.id]
        );
        return {
          ...campaign,
          policy_violations: violations.rows
        };
      })
    );

    res.json({
      ok: true,
      campaigns: campaignsWithViolations
    });
  } catch (error) {
    console.error('Campaigns list error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '캠페인 목록 조회 중 오류가 발생했습니다.'
    });
  }
});

/**
 * GET /campaigns/:id - 캠페인 상세 조회
 */
router.get('/campaigns/:id', appCORS, requireAuth, async (req, res) => {
  const userId = req.user?.id;
  const { id } = req.params;

  try {
    const store = await db.q('SELECT id FROM stores WHERE user_id = $1', [userId]);
    if (!store.rows[0]) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '캠페인을 찾을 수 없습니다.'
      });
    }

    const campaign = await db.q(
      'SELECT * FROM campaigns WHERE id = $1 AND store_id = $2',
      [id, store.rows[0].id]
    );

    if (!campaign.rows[0]) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '캠페인을 찾을 수 없습니다.'
      });
    }

    const violations = await db.q(
      'SELECT * FROM policy_violations WHERE campaign_id = $1',
      [id]
    );

    res.json({
      ok: true,
      campaign: {
        ...campaign.rows[0],
        policy_violations: violations.rows
      }
    });
  } catch (error) {
    console.error('Campaign detail error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '캠페인 상세 조회 중 오류가 발생했습니다.'
    });
  }
});

/**
 * PATCH /campaigns/:id/:action - 캠페인 상태 변경
 */
router.patch('/campaigns/:id/:action', appCORS, requireAuth, express.json(), async (req, res) => {
  const userId = req.user?.id;
  const { id, action } = req.params;
  const { pet_id } = req.body;

  try {
    const store = await db.q('SELECT id FROM stores WHERE user_id = $1', [userId]);
    if (!store.rows[0]) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '캠페인을 찾을 수 없습니다.'
      });
    }

    const campaign = await db.q(
      'SELECT * FROM campaigns WHERE id = $1 AND store_id = $2',
      [id, store.rows[0].id]
    );

    if (!campaign.rows[0]) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '캠페인을 찾을 수 없습니다.'
      });
    }

    let newStatus = campaign.rows[0].status;
    
    if (action === 'pause') {
      newStatus = 'PAUSED';
    } else if (action === 'resume') {
      newStatus = 'RUNNING';
    } else if (action === 'stop') {
      newStatus = 'STOPPED';
    } else if (action === 'change-pet' && pet_id) {
      await db.q('UPDATE campaigns SET pet_id = $1 WHERE id = $2', [pet_id, id]);
    }

    if (newStatus !== campaign.rows[0].status) {
      await db.q('UPDATE campaigns SET status = $1, updated_at = now() WHERE id = $2', [newStatus, id]);
    }

    const updated = await db.q('SELECT * FROM campaigns WHERE id = $1', [id]);

    res.json({
      ok: true,
      campaign: updated.rows[0]
    });
  } catch (error) {
    console.error('Campaign update error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '캠페인 상태 변경 중 오류가 발생했습니다.'
    });
  }
});

module.exports = router;

