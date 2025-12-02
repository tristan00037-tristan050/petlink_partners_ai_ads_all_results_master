require('dotenv').config();

const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const pinoHttp = require('pino-http')();
const bodyParser = require('body-parser');
const cookieParser = require('cookie-parser');

// Middleware
const security = require('./mw/security');
const rateLimit = require('./mw/rateLimit');
const { parseAuth } = require('./mw/authn');
const { authnCookieBridge } = require('./mw/authn_cookie');

// Routes
const healthRouter = require('./routes/health');
const authRouter = require('./routes/auth');
const plansRouter = require('./routes/plans');
const storesRouter = require('./routes/stores');
const petsRouter = require('./routes/pets');
const campaignsRouter = require('./routes/campaigns');
const billingRouter = require('./routes/billing');
const adminRouter = require('./routes/admin');
const metaRouter = require('./routes/meta');
const pgWebhookRouter = require('./routes/pg_webhook');
const pgMockRouter = require('./routes/pg_mock');
const docsRouter = require('./routes/docs');
const adminReportRouter = require('./routes/admin_report');
const bffAuthRouter = require('./routes/bff_auth');

// Jobs
const billingScheduler = require('./jobs/billing_scheduler');
const notifier = require('./jobs/notifier_worker');
const errorMw = require('./mw/error');
const { client, enabled: metricsEnabled } = require('./observability/metrics');

const app = express();

// [FIX] CORS Configuration for Owner Portal (3003) - 가장 먼저 실행
const allowedOrigins = process.env.CORS_ORIGIN?.split(',').map(s => s.trim()) || [
  'http://localhost:3003', // Owner Portal
  'http://localhost:3000', // Default Next.js
  'http://localhost:3001',
  'http://localhost:3002'
];

// CORS 미들웨어를 가장 먼저 설정 (helmet보다 먼저)
app.use(cors({
  origin: function (origin, callback) {
    // origin이 없는 경우(같은 origin 요청, 서버 간 요청 등)도 허용
    if (!origin) {
      return callback(null, true);
    }
    if (allowedOrigins.includes(origin)) {
      return callback(null, true);
    }
    // 허용되지 않은 origin인 경우 - 에러를 throw하지 않고 거부
    callback(null, false);
  },
  credentials: true, // 쿠키/인증 헤더 허용
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Admin-Key', 'X-Admin-Actor'],
  exposedHeaders: ['Content-Type', 'Authorization'],
  preflightContinue: false,
  optionsSuccessStatus: 200
}));

// Security & Observability Middleware
app.use(helmet({
  contentSecurityPolicy: false, // CSP가 CORS 헤더를 방해할 수 있음
  crossOriginResourcePolicy: false, // CORS 미들웨어가 처리
  crossOriginOpenerPolicy: false,   // CORS 미들웨어가 처리
  hsts: false, // HSTS가 CORS 헤더를 방해할 수 있음
}));

app.use(pinoHttp);
app.use(bodyParser.json({ limit: '1mb' }));
app.use(cookieParser());
app.use(authnCookieBridge); // Authorization 없을 때 쿠키에서 주입
app.use(parseAuth);

// Rate Limiting (r4.1)
const rateLimitMw = require('./mw/rateLimit');
app.use('/auth', rateLimitMw);
app.use('/', rateLimitMw);

// Routes Registration
app.use('/healthz', healthRouter);
// /metrics (Prometheus)
if (metricsEnabled) {
  app.get('/metrics', async (_req, res) => {
    res.set('Content-Type', client.register.contentType);
    res.end(await client.register.metrics());
  });
}
// Auth routes (signup, login, me 등)
app.use('/auth', authRouter);
app.use('/plans', plansRouter);
app.use('/stores', storesRouter);
app.use('/pets', petsRouter);
app.use('/campaigns', campaignsRouter);
app.use('/billing', billingRouter);
app.use('/admin', adminRouter);
app.use('/meta', metaRouter); // r7
app.use('/pg/webhook', pgWebhookRouter); // r8
app.use('/docs', docsRouter); // r9
app.use('/admin/reports', adminReportRouter); // r9
app.use('/bff', bffAuthRouter); // r10

// Dev Routes
if (process.env.ENABLE_DEV_MOCK === 'true') {
  app.use('/dev/pg/webhook', pgMockRouter); // r8
}

// (옵션) 프로세스 내 스케줄링 — 운영에선 OS 크론 권장, 스테이징에만 사용
if (process.env.NODE_ENV !== 'production') {
  billingScheduler.schedule('*/15 * * * *'); // 15분마다
  notifier.schedule('*/5 * * * *');         // 5분마다
}

// Error Handling
app.use(errorMw);

const port = process.env.PORT || 5903;
app.listen(port, () => {
  console.log(`[P0 API] listening on :${port}`);
});
