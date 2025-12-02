/**
 * P0: Auth API Routes
 * POST /auth/signup, POST /auth/login, GET /auth/me
 */

const express = require('express');
const crypto = require('crypto');
const db = require('../lib/db');
const { appCORS } = require('../mw/cors_split');
const { requireAuth, issue } = require('../mw/auth');

const router = express.Router();

/**
 * 비밀번호 해시 생성
 */
function hashPassword(password) {
  return crypto.createHash('sha256').update(password).digest('hex');
}

/**
 * POST /auth/signup - 회원가입
 */
router.post('/auth/signup', appCORS, express.json(), async (req, res) => {
  const { email, password, store_name } = req.body;

  if (!email || !password) {
    return res.status(400).json({
      ok: false,
      code: 'INVALID_INPUT',
      message: '이메일과 비밀번호는 필수입니다.'
    });
  }

  if (password.length < 8) {
    return res.status(400).json({
      ok: false,
      code: 'INVALID_PASSWORD',
      message: '비밀번호는 8자 이상이어야 합니다.'
    });
  }

  try {
    // 이메일 중복 확인
    const existing = await db.q('SELECT id FROM users WHERE email = $1', [email]);
    if (existing.rows.length > 0) {
      return res.status(409).json({
        ok: false,
        code: 'EMAIL_EXISTS',
        message: '이미 존재하는 이메일입니다.'
      });
    }

    // 사용자 생성
    const passwordHash = hashPassword(password);
    const user = await db.q(
      'INSERT INTO users (email, password_hash, name) VALUES ($1, $2, $3) RETURNING id, email, created_at',
      [email, passwordHash, store_name || null]
    );

    // 매장 생성 (store_name이 있는 경우)
    let storeId = null;
    if (store_name) {
      const store = await db.q(
        'INSERT INTO stores (user_id, name, short_description) VALUES ($1, $2, $3) RETURNING id',
        [user.rows[0].id, store_name, '매장 정보를 입력해 주세요']
      );
      storeId = store.rows[0].id;
    }

    // JWT 토큰 발급
    const token = issue({ userId: user.rows[0].id, email });

    res.status(201).json({
      ok: true,
      user_id: user.rows[0].id,
      token
    });
  } catch (error) {
    console.error('Signup error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '회원가입 중 오류가 발생했습니다.'
    });
  }
});

/**
 * POST /auth/login - 로그인
 */
router.post('/auth/login', appCORS, express.json(), async (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(401).json({
      ok: false,
      code: 'INVALID_CREDENTIALS',
      message: '이메일과 비밀번호를 입력해 주세요.'
    });
  }

  try {
    const passwordHash = hashPassword(password);
    const user = await db.q(
      'SELECT id, email, created_at FROM users WHERE email = $1 AND password_hash = $2',
      [email, passwordHash]
    );

    if (user.rows.length === 0) {
      return res.status(401).json({
        ok: false,
        code: 'INVALID_CREDENTIALS',
        message: '이메일 또는 비밀번호가 올바르지 않습니다.'
      });
    }

    // 매장 ID 조회
    const store = await db.q('SELECT id FROM stores WHERE user_id = $1', [user.rows[0].id]);
    const storeId = store.rows.length > 0 ? store.rows[0].id : null;

    // JWT 토큰 발급
    const token = issue({ userId: user.rows[0].id, email });

    res.json({
      ok: true,
      user_id: user.rows[0].id,
      token
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '로그인 중 오류가 발생했습니다.'
    });
  }
});

/**
 * GET /auth/me - 현재 사용자 정보
 */
router.get('/auth/me', appCORS, requireAuth, async (req, res) => {
  const userId = req.user?.userId || req.user?.id;

  try {
    const user = await db.q(
      'SELECT id, email, created_at FROM users WHERE id = $1',
      [userId]
    );

    if (user.rows.length === 0) {
      return res.status(404).json({
        ok: false,
        code: 'NOT_FOUND',
        message: '사용자를 찾을 수 없습니다.'
      });
    }

    // 매장 ID 조회
    const store = await db.q('SELECT id FROM stores WHERE user_id = $1', [userId]);
    const storeId = store.rows.length > 0 ? store.rows[0].id : null;

    res.json({
      ok: true,
      user: {
        ...user.rows[0],
        store_id: storeId
      }
    });
  } catch (error) {
    console.error('Get me error:', error);
    res.status(500).json({
      ok: false,
      code: 'INTERNAL_ERROR',
      message: '사용자 정보 조회 중 오류가 발생했습니다.'
    });
  }
});

module.exports = router;

