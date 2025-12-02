/**
 * P0 API Stub Server
 * 개발 모드: DB 없이 즉시 확인 가능한 Express 스텁
 */

const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3800;

// CORS
app.use(cors());
app.use(express.json());

// ============================================================================
// Health Check
// ============================================================================
app.get('/health', (req, res) => {
  res.json({
    ok: true,
    service: 'P0 API Stub',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// ============================================================================
// Plans API
// ============================================================================
app.get('/plans', (req, res) => {
  const plans = [
    {
      id: 1,
      code: 'S',
      name: 'Starter',
      price: 200000,
      ad_budget: 120000,
      features: ['페이스북/인스타그램 또는 틱톡 중 택1', '기본 리포트']
    },
    {
      id: 2,
      code: 'M',
      name: 'Standard',
      price: 400000,
      ad_budget: 300000,
      features: ['페이스북/인스타그램 + 틱톡', '고급 리포트']
    },
    {
      id: 3,
      code: 'L',
      name: 'Pro',
      price: 800000,
      ad_budget: 600000,
      features: ['페이스북/인스타그램 + 틱톡', '프리미엄 리포트']
    }
  ];

  res.json({
    ok: true,
    plans
  });
});

// ============================================================================
// Auth API
// ============================================================================
app.post('/auth/signup', (req, res) => {
  const { email, password, store_name } = req.body;

  // 검증
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

  // 스텁: 항상 성공
  res.status(201).json({
    ok: true,
    user_id: Date.now(), // 임시 ID
    token: 'stub-token-' + Date.now()
  });
});

app.post('/auth/login', (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(401).json({
      ok: false,
      code: 'INVALID_CREDENTIALS',
      message: '이메일과 비밀번호를 입력해 주세요.'
    });
  }

  // 스텁: 항상 성공
  res.json({
    ok: true,
    user_id: 1,
    token: 'stub-token-' + Date.now()
  });
});

// ============================================================================
// Campaigns API (Guard 테스트)
// ============================================================================
app.post('/campaigns', (req, res) => {
  // STORE_PROFILE_INCOMPLETE 가드 시뮬레이션
  res.status(400).json({
    ok: false,
    code: 'STORE_PROFILE_INCOMPLETE',
    message: '매장 정보를 먼저 완성해 주세요.'
  });
});

// ============================================================================
// 서버 시작
// ============================================================================
app.listen(PORT, () => {
  console.log(`P0 API Stub 서버 실행 중: http://localhost:${PORT}`);
  console.log(`Health Check: http://localhost:${PORT}/health`);
});

