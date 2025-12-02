/**
 * P0 Express 서버 스텁
 * OpenAPI 기반 API 엔드포인트 스텁
 */

const express = require('express');
const cors = require('cors');
const app = express();
const PORT = process.env.PORT || 5903;

app.use(cors());
app.use(express.json());

// ============================================================================
// Auth API
// ============================================================================

app.post('/auth/signup', (req, res) => {
  const { email, password, store_name } = req.body;
  
  if (!email || !password) {
    return res.status(400).json({
      ok: false,
      code: 'INVALID_INPUT',
      message: '이메일과 비밀번호는 필수입니다.'
    });
  }

  // 스텁: 항상 성공
  res.status(201).json({
    ok: true,
    user_id: 1,
    token: 'stub-jwt-token-' + Date.now()
  });
});

app.post('/auth/login', (req, res) => {
  const { email, password } = req.body;
  
  if (!email || !password) {
    return res.status(401).json({
      ok: false,
      code: 'INVALID_CREDENTIALS',
      message: '이메일 또는 비밀번호가 올바르지 않습니다.'
    });
  }

  res.json({
    ok: true,
    user_id: 1,
    token: 'stub-jwt-token-' + Date.now()
  });
});

app.get('/auth/me', (req, res) => {
  const authHeader = req.headers.authorization;
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    user: {
      id: 1,
      email: 'store@example.com',
      store_id: 1,
      created_at: new Date().toISOString()
    }
  });
});

// ============================================================================
// Stores API
// ============================================================================

app.get('/stores/me', (req, res) => {
  const authHeader = req.headers.authorization;
  
  if (!authHeader) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  // 스텁: 매장 정보 반환
  res.json({
    ok: true,
    store: {
      id: 1,
      user_id: 1,
      name: '반려동물 분양센터',
      address: '서울시 강남구 테헤란로 123',
      phone: '02-1234-5678',
      business_hours: '평일 10:00-20:00',
      short_description: '책임 있는 분양을 약속합니다',
      description: null,
      images: [],
      is_complete: false,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  });
});

app.put('/stores/me', (req, res) => {
  const authHeader = req.headers.authorization;
  const { name, short_description } = req.body;
  
  if (!authHeader) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  if (!name || !short_description) {
    return res.status(400).json({
      ok: false,
      code: 'STORE_PROFILE_INCOMPLETE',
      message: '매장명과 한 줄 소개는 필수입니다.'
    });
  }

  res.json({
    ok: true,
    store: {
      id: 1,
      ...req.body,
      is_complete: true,
      updated_at: new Date().toISOString()
    }
  });
});

// ============================================================================
// Plans API
// ============================================================================

app.get('/plans', (req, res) => {
  res.json({
    ok: true,
    plans: [
      { id: 1, code: 'S', name: 'Starter', price: 200000, ad_budget: 120000, features: ['페이스북/인스타그램 또는 틱톡 중 택1', '기본 리포트'] },
      { id: 2, code: 'M', name: 'Standard', price: 400000, ad_budget: 300000, features: ['페이스북/인스타그램 + 틱톡', '고급 리포트'] },
      { id: 3, code: 'L', name: 'Pro', price: 800000, ad_budget: 600000, features: ['페이스북/인스타그램 + 틱톡', '프리미엄 리포트'] }
    ]
  });
});

app.get('/stores/me/plan', (req, res) => {
  const authHeader = req.headers.authorization;
  
  if (!authHeader) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    subscription: {
      id: 1,
      store_id: 1,
      plan_id: 1,
      status: 'ACTIVE',
      cycle_start: '2025-11-01',
      cycle_end: '2025-11-30',
      next_billing_date: '2025-12-01',
      last_paid_at: new Date().toISOString(),
      grace_period_days: 1
    }
  });
});

app.post('/stores/me/plan', (req, res) => {
  const authHeader = req.headers.authorization;
  const { plan_id } = req.body;
  
  if (!authHeader) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  if (!plan_id) {
    return res.status(400).json({
      ok: false,
      code: 'INVALID_INPUT',
      message: 'plan_id는 필수입니다.'
    });
  }

  res.json({
    ok: true,
    subscription: {
      id: 1,
      store_id: 1,
      plan_id,
      status: 'ACTIVE',
      cycle_start: '2025-11-01',
      cycle_end: '2025-11-30',
      next_billing_date: '2025-12-01',
      last_paid_at: null,
      grace_period_days: 1
    }
  });
});

// ============================================================================
// Campaigns API
// ============================================================================

app.post('/campaigns', (req, res) => {
  const authHeader = req.headers.authorization;
  const { pet_id, title, body, channels } = req.body;
  
  if (!authHeader) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  // 매장 정보 미완성 검증 (스텁)
  // 실제로는 DB에서 stores.is_complete 확인
  const storeComplete = false; // 스텁: 항상 미완성으로 테스트
  
  if (!storeComplete) {
    return res.status(400).json({
      ok: false,
      code: 'STORE_PROFILE_INCOMPLETE',
      message: '매장 정보를 먼저 완성해 주세요.'
    });
  }

  if (!pet_id || !title || !body || !channels || channels.length === 0) {
    return res.status(400).json({
      ok: false,
      code: 'INVALID_INPUT',
      message: '필수 필드가 누락되었습니다.'
    });
  }

  res.status(201).json({
    ok: true,
    campaign: {
      id: 1,
      store_id: 1,
      pet_id,
      title,
      body,
      hashtags: req.body.hashtags || [],
      images: req.body.images || [],
      videos: req.body.videos || [],
      channels,
      status: 'DRAFT',
      policy_violations: [],
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  });
});

app.get('/campaigns', (req, res) => {
  const authHeader = req.headers.authorization;
  const { status } = req.query;
  
  if (!authHeader) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    campaigns: []
  });
});

app.get('/campaigns/:id', (req, res) => {
  const authHeader = req.headers.authorization;
  const { id } = req.params;
  
  if (!authHeader) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    campaign: {
      id: parseInt(id),
      store_id: 1,
      pet_id: 1,
      title: '샘플 캠페인',
      body: '샘플 본문',
      hashtags: [],
      images: [],
      videos: [],
      channels: ['instagram'],
      status: 'DRAFT',
      policy_violations: [],
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  });
});

app.patch('/campaigns/:id/:action', (req, res) => {
  const authHeader = req.headers.authorization;
  const { id, action } = req.params;
  
  if (!authHeader) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '인증이 필요합니다.'
    });
  }

  const validActions = ['pause', 'resume', 'stop'];
  if (!validActions.includes(action)) {
    return res.status(400).json({
      ok: false,
      code: 'INVALID_ACTION',
      message: '유효하지 않은 액션입니다.'
    });
  }

  res.json({
    ok: true,
    campaign: {
      id: parseInt(id),
      status: action === 'pause' ? 'PAUSED' : action === 'resume' ? 'RUNNING' : 'STOPPED',
      updated_at: new Date().toISOString()
    }
  });
});

// ============================================================================
// Admin API
// ============================================================================

app.get('/admin/stores', (req, res) => {
  const adminKey = req.headers['x-admin-key'];
  
  if (!adminKey || adminKey !== process.env.ADMIN_KEY) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '관리자 인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    stores: []
  });
});

app.patch('/admin/stores/:id/status', (req, res) => {
  const adminKey = req.headers['x-admin-key'];
  const { status } = req.body;
  
  if (!adminKey || adminKey !== process.env.ADMIN_KEY) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '관리자 인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    store: {
      id: parseInt(req.params.id),
      status
    }
  });
});

app.get('/admin/campaigns', (req, res) => {
  const adminKey = req.headers['x-admin-key'];
  
  if (!adminKey || adminKey !== process.env.ADMIN_KEY) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '관리자 인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    campaigns: []
  });
});

app.get('/admin/campaigns/:id', (req, res) => {
  const adminKey = req.headers['x-admin-key'];
  
  if (!adminKey || adminKey !== process.env.ADMIN_KEY) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '관리자 인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    campaign: {
      id: parseInt(req.params.id),
      store_id: 1,
      store_name: '반려동물 분양센터',
      title: '샘플 캠페인',
      thumbnail: null,
      channels: ['instagram'],
      status: 'PENDING_REVIEW',
      policy_violations: [],
      created_at: new Date().toISOString()
    }
  });
});

app.patch('/admin/campaigns/:id/approve', (req, res) => {
  const adminKey = req.headers['x-admin-key'];
  
  if (!adminKey || adminKey !== process.env.ADMIN_KEY) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '관리자 인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    campaign: {
      id: parseInt(req.params.id),
      status: 'APPROVED',
      updated_at: new Date().toISOString()
    }
  });
});

app.patch('/admin/campaigns/:id/reject', (req, res) => {
  const adminKey = req.headers['x-admin-key'];
  const { comment } = req.body;
  
  if (!adminKey || adminKey !== process.env.ADMIN_KEY) {
    return res.status(401).json({
      ok: false,
      code: 'UNAUTHORIZED',
      message: '관리자 인증이 필요합니다.'
    });
  }

  res.json({
    ok: true,
    campaign: {
      id: parseInt(req.params.id),
      status: 'REJECTED_BY_POLICY',
      updated_at: new Date().toISOString()
    }
  });
});

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
// 서버 시작
// ============================================================================

app.listen(PORT, () => {
  console.log(`P0 API Stub 서버 실행 중: http://localhost:${PORT}`);
  console.log(`Health Check: http://localhost:${PORT}/health`);
});

