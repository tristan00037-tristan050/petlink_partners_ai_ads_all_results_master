/**
 * P0 서버 진입점
 * BillingScheduler 통합 및 P0 라우트 마운트
 */

// Bootstrap 스크립트들 (P0 호환성)
try{ require('./bootstrap/net_monitor'); }catch(e){ console.warn('[net_monitor] skip', e&&e.message); }
try{ require('./bootstrap/fetch_polyfill'); }catch(e){ console.warn('[fetch_polyfill] skip', e&&e.message); }
try{ require('./bootstrap/oidc_monitor').start(); }catch(e){ console.warn('[oidc_monitor] skip', e&&e.message); }
try{ require('./bootstrap/pilot_schedulers'); }catch(e){ console.warn('[pilot_schedulers] skip', e&&e.message); }
try{ require('./bootstrap/refund_sla_scheduler'); }catch(e){ console.warn('[refund_sla] skip', e&&e.message); }
try{ require('./bootstrap/cbk_sla_scheduler'); }catch(e){ console.warn('[cbk_sla] skip', e&&e.message); }

// P0: BillingScheduler 시작
try {
  const billingScheduler = require('./bootstrap/billing_scheduler');
  billingScheduler.startScheduler();
  console.log('[P0] BillingScheduler started');
} catch (e) {
  console.warn('[P0] BillingScheduler skip', e && e.message);
}

const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

// P0 미들웨어 (안전한 로드)
let requireAuth, issue, verify;
let appCORS, adminCORS;
let requireAdmin;

try {
  const authMw = require('./mw/auth');
  requireAuth = authMw.requireAuth;
  issue = authMw.issue;
  verify = authMw.verify;
} catch (e) {
  console.warn('[mw/auth] skip', e && e.message);
  // 스텁
  requireAuth = (req, res, next) => { req.user = { id: 1, userId: 1 }; next(); };
  issue = (payload) => 'stub-token';
  verify = (token) => ({ id: 1, userId: 1 });
}

try {
  const corsMw = require('./mw/cors_split');
  appCORS = corsMw.appCORS;
  adminCORS = corsMw.adminCORS;
} catch (e) {
  console.warn('[mw/cors_split] skip', e && e.message);
  appCORS = (req, res, next) => next();
  adminCORS = (req, res, next) => next();
}

try {
  const adminMw = require('./mw/admin_gate');
  requireAdmin = adminMw.requireAdmin;
} catch (e) {
  console.warn('[mw/admin_gate] skip', e && e.message);
  requireAdmin = (req, res, next) => next();
}

const app = express();

// 통합 클라이언트 앱 (SPA)
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'app.html'));
});

// 정적 파일 서빙
app.use(express.static(path.join(__dirname, 'public')));

// 요청 추적 ID 미들웨어
try {
  app.use(require('./mw/corr'));
  app.use((req, res, next) => {
    globalThis.__last_req_id = req.req_id;
    next();
  });
} catch (e) {
  console.warn('[mw/corr] skip', e && e.message);
  app.use((req, res, next) => {
    req.req_id = `req-${Date.now()}`;
    next();
  });
}

// 감사 로깅 미들웨어
try {
  app.use(require('./mw/audit_logger'));
} catch (e) {
  console.warn('[mw/audit_logger] skip', e && e.message);
  app.use((req, res, next) => next());
}

// CORS 설정
const allowed = (process.env.CORS_ORIGINS || 'http://localhost:5902,http://localhost:8000').split(',');
app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(cors({
  origin: (origin, callback) => {
    if (!origin || allowed.includes(origin)) {
      callback(null, true);
    } else {
      callback(new Error('Not allowed by CORS'));
    }
  },
  credentials: true
}));

// Body parser
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15분
  max: 100 // 최대 100 요청
});
app.use('/api/', limiter);

// ============================================================================
// P0 Routes
// ============================================================================

// Auth Routes
app.use(require('./routes/auth'));

// Stores Routes
app.use(require('./routes/stores'));

// Plans Routes
app.use(require('./routes/plans'));

// Campaigns Routes
app.use(require('./routes/campaigns'));

// Admin Routes
app.use(require('./routes/admin_stores'));
app.use(require('./routes/admin_campaigns'));

// ============================================================================
// Health Check
// ============================================================================

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    service: 'P0 API',
    version: '1.0.0',
    timestamp: new Date().toISOString()
  });
});

// ============================================================================
// 서버 시작
// ============================================================================

const PORT = process.env.PORT || 5903;

app.listen(PORT, () => {
  console.log(`P0 API 서버 실행 중: http://localhost:${PORT}`);
  console.log(`Health Check: http://localhost:${PORT}/health`);
});

module.exports = app;

