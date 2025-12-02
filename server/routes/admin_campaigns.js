/**
 * P0: Admin Campaigns API Routes
 * GET /admin/campaigns, GET /admin/campaigns/:id, PATCH /admin/campaigns/:id/approve|reject
 */

const express = require('express');
const db = require('../lib/db');
const { adminCORS } = require('../mw/cors_split');
const { requireAdmin } = require('../mw/admin_gate');

const router = express.Router();

/**
 * GET /admin/campaigns - 광고 목록 조회
 */
router.get('/admin/campaigns', adminCORS, requireAdmin, async (req, res) => {
  const { q, status, store_id } = req.query;

  try {
    let query = `
      SELECT 
        c.*,
        s.name as store_name,
        s.user_id,
        u.email as store_email
      FROM campaigns c
      JOIN stores s ON c.store_id = s.id
      JOIN users u ON s.user_id = u.id
      WHERE 1=1
    `;
    const params = [];
    let paramIndex = 1;

    // 검색어 필터
    if (q) {
      query += ` AND (c.title ILIKE $${paramIndex} OR s.name ILIKE $${paramIndex})`;
      params.push(`%${q}%`);
      paramIndex++;
    }

    // 상태 필터
    if (status) {
      query += ` AND c.status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    // 매장 ID 필터
    if (store_id) {
      query += ` AND c.store_id = $${paramIndex}`;
      params.push(parseInt(store_id));
      paramIndex++;
    }

    query += ' ORDER BY c.created_at DESC LIMIT 100';

    const campaigns = await db.q(query, params);

    // 각 캠페인의 policy_violations 조회
    const campaignsWithViolations = await Promise.all(
      campaigns.rows.map(async (campaign) => {
        const violations = await db.q(
          'SELECT * FROM policy_violations WHERE campaign_id = $1',
          [campaign.id]
        );
        return {
          id: campaign.id,
          store_id: campaign.store_id,
          store_name: campaign.store_name,
          title: campaign.title,
          thumbnail: campaign.images && campaign.images.length > 0 ? campaign.images[0] : null,
          channels: campaign.channels,
          status: campaign.status,
          policy_violations: violations.rows,
          created_at: campaign.created_at
        };
      })
    );

    res.json({
      ok: true,
      campaigns: campaignsWithViolations
    });
  } catch (error) {
    console.error('Admin campaigns list error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '광고 목록 조회 중 오류가 발생했습니다.'
    });
  }
});

/**
 * GET /admin/campaigns/:id - 광고 상세 조회
 */
router.get('/admin/campaigns/:id', adminCORS, requireAdmin, async (req, res) => {
  const { id } = req.params;

  try {
    const campaign = await db.q(`
      SELECT 
        c.*,
        s.name as store_name,
        s.user_id,
        u.email as store_email
      FROM campaigns c
      JOIN stores s ON c.store_id = s.id
      JOIN users u ON s.user_id = u.id
      WHERE c.id = $1
    `, [id]);

    if (!campaign.rows[0]) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '광고를 찾을 수 없습니다.'
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
        store_name: campaign.rows[0].store_name,
        policy_violations: violations.rows
      }
    });
  } catch (error) {
    console.error('Admin campaign detail error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '광고 상세 조회 중 오류가 발생했습니다.'
    });
  }
});

/**
 * PATCH /admin/campaigns/:id/approve - 광고 승인
 */
router.patch('/admin/campaigns/:id/approve', adminCORS, requireAdmin, async (req, res) => {
  const { id } = req.params;

  try {
    // 캠페인 조회
    const campaign = await db.q('SELECT * FROM campaigns WHERE id = $1', [id]);

    if (!campaign.rows[0]) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '광고를 찾을 수 없습니다.'
      });
    }

    // 상태가 PENDING_REVIEW인 경우만 승인 가능
    if (campaign.rows[0].status !== 'PENDING_REVIEW') {
      return res.status(400).json({
        ok: false,
        code: 'INVALID_STATUS',
        message: '심사중인 광고만 승인할 수 있습니다.'
      });
    }

    // 상태를 APPROVED로 변경
    await db.q(
      'UPDATE campaigns SET status = $1, updated_at = now() WHERE id = $2',
      ['APPROVED', id]
    );

    const updated = await db.q('SELECT * FROM campaigns WHERE id = $1', [id]);
    const violations = await db.q(
      'SELECT * FROM policy_violations WHERE campaign_id = $1',
      [id]
    );

    res.json({
      ok: true,
      campaign: {
        ...updated.rows[0],
        policy_violations: violations.rows
      }
    });
  } catch (error) {
    console.error('Admin campaign approve error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '광고 승인 중 오류가 발생했습니다.'
    });
  }
});

/**
 * PATCH /admin/campaigns/:id/reject - 광고 반려
 */
router.patch('/admin/campaigns/:id/reject', adminCORS, requireAdmin, express.json(), async (req, res) => {
  const { id } = req.params;
  const { comment } = req.body;

  try {
    // 캠페인 조회
    const campaign = await db.q('SELECT * FROM campaigns WHERE id = $1', [id]);

    if (!campaign.rows[0]) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '광고를 찾을 수 없습니다.'
      });
    }

    // 상태가 PENDING_REVIEW인 경우만 반려 가능
    if (campaign.rows[0].status !== 'PENDING_REVIEW') {
      return res.status(400).json({
        ok: false,
        code: 'INVALID_STATUS',
        message: '심사중인 광고만 반려할 수 있습니다.'
      });
    }

    // 상태를 REJECTED_BY_POLICY로 변경
    await db.q(
      'UPDATE campaigns SET status = $1, updated_at = now() WHERE id = $2',
      ['REJECTED_BY_POLICY', id]
    );

    // 반려 사유를 policy_violations에 기록 (옵션)
    if (comment) {
      await db.q(`
        INSERT INTO policy_violations (campaign_id, type, field, message)
        VALUES ($1, $2, $3, $4)
      `, [id, 'ADMIN_REJECT', 'admin', comment]);
    }

    const updated = await db.q('SELECT * FROM campaigns WHERE id = $1', [id]);
    const violations = await db.q(
      'SELECT * FROM policy_violations WHERE campaign_id = $1',
      [id]
    );

    res.json({
      ok: true,
      campaign: {
        ...updated.rows[0],
        policy_violations: violations.rows
      }
    });
  } catch (error) {
    console.error('Admin campaign reject error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '광고 반려 중 오류가 발생했습니다.'
    });
  }
});

module.exports = router;

