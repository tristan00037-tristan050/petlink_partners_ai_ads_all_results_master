require('./bootstrap/net_monitor');
require('./bootstrap/fetch_polyfill');
try{ require('./bootstrap/oidc_monitor').start(); }catch(e){ console.warn('[oidc_monitor] skip', e&&e.message); }
try{ require('./bootstrap/pilot_schedulers'); }catch(e){ console.warn('[pilot_schedulers] skip', e&&e.message); }
try{ require('./bootstrap/refund_sla_scheduler'); }catch(e){ console.warn('[refund_sla] skip', e&&e.message); }
require('./bootstrap/cbk_sla_scheduler');
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const { requireAuth, issue, verify } = require('./mw/auth');
const { checkCopy, suggestCopy } = require('./lib/copy_engine');
const {
    prefsSchema,
    radiusSchema,
    weightsSchema,
    pacerPreviewSchema,
    pacerApplySchema,
    animalSchema,
    draftSchema,
    ingestSchema
} = require('./lib/validators');
const { routePostings } = require('./connectors');
const { queues, ensureQueues } = require('./queue/bull');

const app = express();

// 통합 클라이언트 앱 (SPA)
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'app.html'));
});

// 레거시 랜딩 페이지 (리다이렉트)
app.get('/landing.html', (req, res) => {
  res.redirect('/');
});

// 정적 파일 서빙 (public 디렉토리)
app.use(express.static(path.join(__dirname, 'public')));

// SSO 브리지 UI 서빙 (보안 헤더 적용)
const securityHeaders = require('./mw/security_headers');
app.use('/app-ui', securityHeaders, express.static(path.join(__dirname, 'public', 'app-ui')));
app.use('/admin-ui', securityHeaders, express.static(path.join(__dirname, 'public', 'admin-ui')));

// frontend 디렉토리 서빙 (로그인/회원가입 등 클라이언트 화면)
app.use('/frontend', express.static(path.join(__dirname, '..', 'frontend')));

// 간단한 URL로 landing.html 접근
app.get('/landing.html', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'landing.html'));
});

// 간단한 URL로 다른 페이지들 접근
app.get('/pricing.html', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'pricing.html'));
});

app.get('/pet-register.html', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'pet-register.html'));
});

app.get('/help.html', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'help.html'));
});

app.get('/auth.html', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'auth.html'));
});

app.get('/mypage.html', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'mypage.html'));
});

app.get('/how-ads-work.html', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'how-ads-work.html'));
});

app.get('/dashboard.html', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'frontend', 'dashboard.html'));
});

// 통합 대시보드 (어드민용)
app.get('/admin-dashboard', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// 요청 추적 ID 미들웨어 (가장 먼저 적용)
app.use(require('./mw/corr'));
app.use((req,res,next)=>{ globalThis.__last_req_id = req.req_id; next(); });

// 감사 로깅 미들웨어
app.use(require('./mw/audit_logger'));

const allowed = (process.env.CORS_ORIGINS || 'http://localhost:5902,http://localhost:8000').split(',');

app.use(helmet({ crossOriginResourcePolicy: false }));
app.use(require('./mw/security_headers')); // 보안 헤더 상수화
app.use(rateLimit({ windowMs: 60 * 1000, max: 120 }));
app.use(cors({
    origin: (o, cb) => {
        if (!o) return cb(null, true);
        return cb(null, allowed.some(x => o.startsWith(x)));
    },
    credentials: true
}));

app.use('/billing/webhook/pg', require('express').raw({ type: 'application/json' }));
app.use("/ads/billing/webhook/pg", require("express").raw({ type: "application/json" }));
// Pilot 라우트를 먼저 등록 (더 구체적인 경로)
app.use('/admin/reports', require('./routes/admin_pilot_autopush'));
app.use('/admin/reports', require('./routes/admin_pilot_snapshots'));
app.use('/admin/reports', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_pilot_trends'));
app.use('/admin/reports', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_home_fast'));
app.use('/admin/reports', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_pilot_scheduler'));
app.use('/admin/reports', require('./routes/admin_quality'));
app.get('/openapi_quality.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','quality.yaml')));
app.use('/ads/billing', require('./routes/ads_billing_charge'));
app.use('/admin/ads/billing', require('./routes/admin_bootpay_network'));
app.use('/admin/ads/billing', require('./routes/admin_billing_ready'));
app.get('/openapi_ready_quality.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ready_quality.yaml')));
app.get('/openapi_ready_quality.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ready_quality.yaml')));
app.get('/openapi_ready_quality.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ready_quality.yaml')));
app.use('/admin', require('./mw/admin_ratelimit'));
app.use(express.json({ limit: '4mb' })); // 기본 바디 제한

// 정책 마운트 (RBAC)
const policies = require('./mw/policy_mounts');
policies.mountBillingPolicies(app);
policies.mountProfilePolicies(app);

// 리프레시 토큰 라우트
app.use('/auth', require('./routes/auth_refresh'));

// App 상태 캐시 (appCORS 내부)
app.use('/', (require('./mw/cors_split')?.appCORS)||((req,res,next)=>next()), require('./routes/app_pilot_status_cache'));

// SSO 시작 라우트
app.use(require('./routes/app_sso_start'));
app.use(require('./routes/admin_sso_start'));

// 보안 헤더가 적용된 정적 파일 라우트
app.use(require('./routes/static_secure'));

// App 측 메트릭 수집 (CORS 경계 내부)
app.use('/app', (require('./mw/cors_split')?.appCORS)||((req,res,next)=>next()), require('./routes/app_metrics_collect'));

// Admin 측 메트릭 수집/요약/게이트 (CORS 경계 내부)
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_metrics_collect'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_session_metrics'));

// OpenAPI 문서
app.get('/openapi_pilot_autopush.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','pilot_autopush.yaml')));
app.get('/openapi_pilot_snapshots.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','pilot_snapshots.yaml')));
app.get('/openapi_pilot_trends.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','pilot_trends.yaml')));
app.get('/openapi_pilot_flip_rca.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','pilot_flip_rca.yaml')));
app.get('/openapi_pilot_final.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','pilot_final.yaml')));
app.get('/openapi_prod_change.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','prod_change.yaml')));
app.get('/openapi_prod_live_billing.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','prod_live_billing.yaml')));
app.get('/openapi_subs_ramp.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','subs_ramp.yaml')));
app.get('/openapi_ramp_reports.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ramp_reports.yaml')));
app.get('/openapi_ledger.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ledger.yaml')));
app.get('/openapi_ledger_periods.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ledger_periods.yaml')));
app.get('/openapi_ledger_r112.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ledger_r112.yaml')));
app.get('/openapi_payout_orch.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','payout_orch.yaml')));
app.get('/openapi_payout_channels.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','payout_channels.yaml')));
app.get('/openapi_golive_bundle.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','golive_bundle.yaml')));
app.get('/openapi_tday.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','tday.yaml')));
app.get('/openapi_cutover_tv.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','cutover_tv.yaml')));
app.get('/openapi_chargebacks.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','chargebacks.yaml')));
app.get('/openapi_chargebacks_r119.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','chargebacks_r119.yaml')));
app.get('/openapi_period_cbk_integration.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','period_cbk_integration.yaml')));
app.get('/openapi_chargebacks_r121.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','chargebacks_r121.yaml')));

// Admin SPA 라우트 (더 구체적인 경로를 먼저)
app.use('/admin', require('./routes/admin_auth'));
app.use('/admin', require('./routes/admin_audit_logs'));
app.use('/admin', require('./routes/admin_spa_gate'));
app.use('/admin', require('./routes/admin_oidc_status'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_pilot_home3'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_pilot_flip_rca'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_pilot_final'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_pilot_acksla'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_prod_preflight'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_prod_change'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_billing_live'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_rollout_assign'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_subs_ramp'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_subs_policy_ui'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_ramp_reports'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_ledger'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_ledger_periods'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_ledger_ui'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_recon_assist'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_refund_incidents'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_payout_orch'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_payout_channels'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_golive_bundle'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_tday'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_cutover_panel'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_tv'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_chargebacks'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_chargebacks_extras'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_ledger_periods_cbk'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_payout_orch_cbk'));
app.use('/admin', (require('./mw/cors_split')?.adminCORS)||((req,res,next)=>next()), require('./routes/admin_chargebacks_ui'));

// 어드민 감사 조회 라우트 (기존)
app.use('/admin/audit', require('./routes/admin_audit'));

// CORS 분리 검증용 핑 엔드포인트
app.get('/_ping/app', (req,res)=>res.set('Access-Control-Allow-Origin', process.env.APP_ORIGIN||'http://localhost:3000').json({ok:true,who:'app'}));
app.get('/_ping/admin', (req,res)=>res.set('Access-Control-Allow-Origin', process.env.ADMIN_ORIGIN||'http://localhost:8000').json({ok:true,who:'admin'}));
app.use('/admin/advertisers', require('./mw/admin').requireAdmin, require('./routes/admin_advertisers'));app.use('/admin/advertisers', require('./mw/admin').requireAdmin, require('./routes/admin_advertisers_extras'));
app.get('/openapi_admin_advertisers_extras.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','admin_advertisers_extras.yaml')));app.use('/admin', require('./routes/admin_autoreview'));
app.use('/admin', require('./routes/admin_subscriptions'));
app.use('/ads', require('./routes/ads_quality_alias'));
app.use('/admin/webapp', require('./routes/admin_webapp_loop'));
app.use('/admin/ads/quality', require('./routes/admin_quality_rules'));
app.use('/admin', require('./routes/admin_webapp_gate'));
app.get('/openapi_webapp_gate.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','webapp_gate.yaml')));
app.get('/admin/ads/billing/ui',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ui','ads_billing_ui.html')));
app.use(require('express').static(require('path').join(__dirname,'../public')));
app.get('/manifest.json',(req,res)=>res.sendFile(require('path').join(__dirname,'../public','manifest.json')));
app.get('/service-worker.js',(req,res)=>res.sendFile(require('path').join(__dirname,'public','service-worker.js')));
app.get('/admin/ads/quality/ui',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ui','ads_quality_ui.html')));
app.use('/ads/quality', require('./routes/ads_quality'));
app.get('/openapi_ads_quality.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','ads_quality.yaml')));
app.use('/advertiser', require('./routes/advertiser_profile'));
app.use('/ads', require('./routes/ads_validate'));
app.get('/openapi_monitor_v2.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','monitor_v2.yaml')));
app.get('/openapi_monitor_v2.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','monitor_v2.yaml')));
app.get('/openapi_monitor_v2.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','monitor_v2.yaml')));
app.get('/openapi_monitor_v2.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','monitor_v2.yaml')));
app.get('/openapi_monitor_v2.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','monitor_v2.yaml')));
app.use('/admin', require('./routes/admin_evidence_v3'));
app.use('/admin', require('./routes/admin_monitor_v2'));
app.use('/admin/ads/billing', require('./routes/admin_billing_gate_final'));
app.use('/admin/reports', require('./routes/admin_quality_alerts'));
app.use('/admin/reports', require('./routes/admin_quality_thresholds_ui'));
app.use('/admin/reports', require('./routes/admin_quality_thresholds_api'));
app.use('/admin/ads/billing', require('./routes/admin_billing_monitor'));
app.use('/admin/ads/billing', require('./routes/admin_billing_livecheck'));
app.use('/admin/reports', require('./mw/admin').requireAdmin, require('./routes/admin_quality_thresholds'));
app.use('/admin/reports', require('./mw/admin').requireAdmin, require('./routes/admin_reports'));
app.get('/openapi_admin_alerts.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','admin_alerts.yaml')));
app.use("/ads/billing/payment-methods", require("./routes/ads_payment_methods"));
app.use("/ads/billing", require("./routes/ads_billing"));
app.use("/admin/ads/billing", require("./mw/admin").requireAdmin);
app.use("/admin/ads/billing", require("./routes/ads_billing_admin"));
app.use('/admin/ads/billing', require('./routes/admin_bootpay_preflight'));
app.get("/openapi_ads_billing.yaml", (req, res) => res.sendFile(require("path").join(__dirname, "openapi", "ads_billing.yaml")));
app.get("/docs-ads-billing", (req, res) => res.sendFile(require("path").join(__dirname, "openapi", "ads_billing.html")));
// 소비자 결제 라우트 (ENABLE_CONSUMER_BILLING=false일 때 비활성)
// app.use('/billing', require('./routes/payments_refund'));
// app.use('/billing', require('./routes/payments'));
app.get('/openapi_r51.yaml',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','r51.yaml')));
app.get('/docs-payments',(req,res)=>res.sendFile(require('path').join(__dirname,'openapi','payments.html')));
app.use(require('./mw/idempotency')());
app.use('/docs', require('express').static(require('path').join(__dirname, 'openapi')));
app.get('/openapi.yaml', (req, res) => res.sendFile(require('path').join(__dirname, 'openapi', 'petlink.yaml')));
app.use('/admin/outbox', require('./mw/admin').requireAdmin, require('./lib/outbox').adminRouter());
app.use('/admin/settlements', require('./mw/admin').requireAdmin, require('./routes/admin_settlements'));
app.use('/admin/ops/compliance', require('./mw/admin').requireAdmin, require('./routes/admin_compliance'));
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
app.use('/admin/ops', require('./mw/admin').requireAdmin, require('./routes/admin/housekeeping'));
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
require('./lib/outbox').startWorker();
app.use('/web', express.static(path.join(__dirname, '..', 'web')));

// CORS 에러 핸들러 (B4)
app.use((err, req, res, next) => {
    if (String(err && err.message).includes('CORS_NOT_ALLOWED')) {
        return res.status(403).json({ ok: false, error: 'CORS_NOT_ALLOWED' });
    }
    return next(err);
});

// r4 오버레이: 멱등성, Outbox, OpenAPI (express.json 이후, 라우트 등록 이전)
try {
    require('./lib/outbox').startWorker();
} catch (e) {
    console.warn('[r4] 오버레이 로드 실패 (계속 진행):', e.message);
}

let seqStore = 1, seqAnimal = 1, seqDraft = 1, seqInv = 1;

const storePrefs = new Map();
const storeRadius = new Map();
const storeWeights = new Map();
const animals = new Map();
const drafts = new Map();
const schedules = new Map();

const metrics = {
    totals: { impressions: 0, views: 0, clicks: 0, cost: 0, dm: 0, call: 0, route: 0, lead: 0 },
    byChannel: {},
    byStore: {}
};

const invoices = new Map();
const DEF_PREF = { ig_enabled: true, tt_enabled: true, yt_enabled: false, kakao_enabled: false, naver_enabled: false };
const DEF_W = { mon: 1, tue: 1, wed: 1, thu: 1.05, fri: 1.15, sat: 1.30, sun: 1.25, holiday: 1.30, holidays: [] };

const effChs = (sid) => {
    const p = storePrefs.get(sid) || DEF_PREF;
    const a = [];
    if (p.ig_enabled) a.push('META');
    if (p.tt_enabled) a.push('TIKTOK');
    if (p.yt_enabled) a.push('YOUTUBE');
    if (p.kakao_enabled) a.push('KAKAO');
    if (p.naver_enabled) a.push('NAVER');
    return a;
};

const todayStr = () => new Date().toISOString().slice(0, 10);

function addSpend(store_id, costKRW) {
    const ds = todayStr();
    metrics.byStore[store_id] = metrics.byStore[store_id] || {};
    const s = metrics.byStore[store_id];
    s[ds] = (s[ds] || 0) + costKRW;
}

async function guardPacing(store_id) {
    const now = new Date();
    const month = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
    const s = schedules.get(`${store_id}:${month}`);
    if (!s) return;
    
    const ds = todayStr();
    const day = s.schedule.find(x => x.date === ds);
    if (!day) return;
    
    const spent = (metrics.byStore[store_id] && metrics.byStore[store_id][ds]) || 0;
    if (spent >= day.max) throw new Error('DAILY_CAP_REACHED');
}

// 공개 엔드포인트
app.get('/health', (_q, r) => r.json({ ok: true, ts: new Date().toISOString() }));

// 개발 편의: 가입 즉시 토큰 발급(운영에서는 제거)
app.post('/auth/signup', (q, r) => {
    const id = seqStore++;
    storePrefs.set(id, { ...DEF_PREF });
    storeRadius.set(id, 6);
    storeWeights.set(id, { ...DEF_W });
    const token = issue(id, 24 * 60 * 60);
    r.json({ ok: true, store_id: id, token });
});

// dev 토큰 발급(옵션)
if (process.env.DEV_AUTH === '1') {
    app.get('/auth/dev-token', (q, r) => {
        const id = Number(q.query.store_id || 1);
        return r.json({ ok: true, token: issue(id) });
    });
}

// 인증 미들웨어(보호 라우트)
// 공개 경로: /health, /auth/*, /web, /frontend, /landing.html, /pricing.html, /help.html, /pet-register.html, /how-ads-work.html, /dashboard.html
app.use((req, res, next) => {
  // 정적 파일 및 공개 HTML 페이지는 인증 없이 접근 가능
  const publicPaths = [
    '/health', 
    '/auth/signup', 
    '/auth/dev-token', 
    '/auth/login',
    '/web',
    '/frontend',
    '/landing.html',
    '/pricing.html',
    '/help.html',
    '/pet-register.html',
    '/how-ads-work.html',
    '/dashboard.html',
    '/auth.html',
    '/mypage.html',
    '/ads-management.html',
    '/franchise-management.html',
    '/store-register.html'
  ];
  
  const isPublic = publicPaths.some(p => req.path === p || req.path.startsWith(p));
  if (isPublic) {
    return next();
  }
  
  // 그 외 경로는 requireAuth 적용
  return requireAuth([])(req, res, next);
});

// 채널 설정
app.get('/stores/:id/channel-prefs', (q, r) => {
    if (+q.params.id !== q.storeId) return r.status(403).json({ ok: false, error: 'FORBIDDEN' });
    r.json(storePrefs.get(q.storeId) || DEF_PREF);
});

app.put('/stores/:id/channel-prefs', (q, r) => {
    if (+q.params.id !== q.storeId) return r.status(403).json({ ok: false, error: 'FORBIDDEN' });
    const p = prefsSchema.safeParse(q.body || {});
    if (!p.success) return r.status(400).json({ ok: false, error: 'BAD_PREFS' });
    const cur = storePrefs.get(q.storeId) || DEF_PREF;
    const n = { ...cur, ...p.data };
    storePrefs.set(q.storeId, n);
    r.json({ ok: true, prefs: n });
});

// 반경/가중치
app.get('/stores/:id/radius', (q, r) => {
    if (+q.params.id !== q.storeId) return r.status(403).json({ ok: false });
    r.json({ radius_km: storeRadius.get(q.storeId) || 6 });
});

app.put('/stores/:id/radius', (q, r) => {
    if (+q.params.id !== q.storeId) return r.status(403).json({ ok: false });
    const v = radiusSchema.safeParse(q.body || {});
    if (!v.success) return r.status(400).json({ ok: false, error: 'BAD_RADIUS' });
    storeRadius.set(q.storeId, v.data.radius_km);
    r.json({ ok: true, radius_km: v.data.radius_km });
});

app.get('/stores/:id/weights', (q, r) => {
    if (+q.params.id !== q.storeId) return r.status(403).json({ ok: false });
    r.json(storeWeights.get(q.storeId) || DEF_W);
});

app.put('/stores/:id/weights', (q, r) => {
    if (+q.params.id !== q.storeId) return r.status(403).json({ ok: false });
    const v = weightsSchema.safeParse(q.body || {});
    if (!v.success) return r.status(400).json({ ok: false, error: 'BAD_WEIGHTS' });
    const c = storeWeights.get(q.storeId) || DEF_W;
    storeWeights.set(q.storeId, { ...c, ...v.data });
    r.json({ ok: true, weights: storeWeights.get(q.storeId) });
});

// 페이싱 프리뷰/적용
app.post('/pacer/preview', (q, r) => {
    const v = pacerPreviewSchema.safeParse(q.body || {});
    if (!v.success) return r.status(400).json({ ok: false });
    const { store_id, month, remaining_budget, band_pct = 20 } = v.data;
    if (store_id !== q.storeId) return r.status(403).json({ ok: false });
    
    const w = storeWeights.get(store_id) || DEF_W;
    const [y, m] = month.split('-').map(Number);
    const days = new Date(y, m, 0).getDate();
    const hol = new Set((w.holidays || []).map(s => String(s).trim()));
    const ww = [], ds = [];
    
    for (let d = 1; d <= days; d++) {
        const dt = new Date(Date.UTC(y, m - 1, d));
        const dow = dt.getUTCDay();
        let k = (dow === 0 ? w.sun : dow === 6 ? w.sat : [w.mon, w.tue, w.wed, w.thu, w.fri][dow - 1]);
        const iso = dt.toISOString().slice(0, 10);
        if (hol.has(iso)) k *= (w.holiday || 1);
        ww.push(Math.max(0.0001, k));
        ds.push(iso);
    }
    
    const sum = ww.reduce((a, b) => a + b, 0);
    const band = (+band_pct) / 100;
    const schedule = ds.map((d, i) => {
        const a = remaining_budget * (ww[i] / sum);
        return { date: d, amount: Math.round(a), min: Math.round(a * (1 - band)), max: Math.round(a * (1 + band)) };
    });
    
    r.json({ ok: true, schedule });
});

app.post('/pacer/apply', (q, r) => {
    const v = pacerApplySchema.safeParse(q.body || {});
    if (!v.success) return r.status(400).json({ ok: false });
    if (v.data.store_id !== q.storeId) return r.status(403).json({ ok: false });
    schedules.set(`${q.storeId}:${v.data.month}`, { schedule: v.data.schedule, appliedAt: new Date().toISOString() });
    r.json({ ok: true, stored: v.data.schedule.length });
});

app.get('/engine/today', (q, r) => {
    const sid = q.storeId;
    const now = new Date();
    const month = `${now.getUTCFullYear()}-${String(now.getUTCMonth() + 1).padStart(2, '0')}`;
    const s = schedules.get(`${sid}:${month}`);
    const ds = now.toISOString().slice(0, 10);
    const d = s && s.schedule.find(x => x.date === ds);
    if (!d) return r.json({ ok: false, error: 'NO_SCHEDULE', month });
    r.json({ ok: true, store_id: sid, date: ds, target: d.amount, min: d.min, max: d.max });
});

// 동물 등록(정책/카피 가드 + 미디어 큐 옵션)
app.post('/animals', (q, r) => {
    const v = animalSchema.safeParse(q.body || {});
    if (!v.success) return r.status(400).json({ ok: false, error: 'BAD_ANIMAL' });
    if (v.data.store_id !== q.storeId) return r.status(403).json({ ok: false });
    
    const c = checkCopy(`${v.data.title || ''}\n${v.data.caption || ''}\n${v.data.note || ''}`);
    if (!c.ok) return r.status(422).json({ ok: false, code: 'POLICY_TEXT_VIOLATION', message: c.message, suggestion: suggestCopy() });
    
    const id = seqAnimal++;
    animals.set(id, { id, ...v.data, ts: new Date().toISOString() });
    
    if (process.env.ENABLE_MEDIA_PIPELINE === '1') {
        ensureQueues();
        queues.image.add('process', { animal_id: id });
        queues.video.add('process', { animal_id: id });
    }
    
    r.status(201).json({ ok: true, animal_id: id, scheduled: effChs(q.storeId) });
});

// 오가닉 초안 → 승인(실패 시 초안 폴백 + 서명 승인토큰 발행)
app.post('/organic/drafts', (q, r) => {
    const v = draftSchema.safeParse(q.body || {});
    if (!v.success) return r.status(400).json({ ok: false });
    if (v.data.store_id !== q.storeId) return r.status(403).json({ ok: false });
    
    const c = checkCopy(v.data.copy || '');
    if (!c.ok) return r.status(422).json({ ok: false, code: 'POLICY_TEXT_VIOLATION', message: c.message, suggestion: suggestCopy() });
    
    const id = seqDraft++;
    drafts.set(id, {
        id,
        store_id: q.storeId,
        animal_id: (v.data.animal_id || 0),
        channels: v.data.channels,
        copy: v.data.copy || '',
        status: 'DRAFT',
        ts: new Date().toISOString(),
        history: []
    });
    r.status(201).json({ ok: true, draft_id: id });
});

app.get('/organic/drafts', (q, r) => {
    r.json({ ok: true, items: [...drafts.values()].filter(d => d.store_id === q.storeId) });
});

app.post('/organic/drafts/:id/publish', async (q, r) => {
    const d = drafts.get(+q.params.id);
    if (!d || d.store_id !== q.storeId) return r.status(404).json({ ok: false });
    
    try {
        await guardPacing(q.storeId);
    } catch (e) {
        return r.status(409).json({ ok: false, error: String(e.message) });
    }
    
    const storeCh = effChs(q.storeId);
    const chans = (d.channels && d.channels.length ? d.channels : storeCh);
    const res = await routePostings({ draft: d, channels: chans });
    
    d.history.push({ at: new Date().toISOString(), action: 'publish', channels: chans, res });
    d.status = (res.every(x => x.status === 'POSTED') ? 'PUBLISHED' : 'PARTIAL');
    d.published_at = new Date().toISOString();
    d.results = res;
    
    r.json({ ok: true, draft: d });
});

app.post('/organic/drafts/:id/retry', (q, r) => {
    try {
        const token = String((q.body || {}).token || '');
        const data = verify(token);
        const d = drafts.get(+q.params.id);
        if (!d || d.store_id !== q.storeId) return r.status(404).json({ ok: false });
        if (data.draft_id !== d.id) return r.status(403).json({ ok: false, error: 'BAD_TOKEN_TARGET' });
        
        d.history.push({ at: new Date().toISOString(), action: 'retry', token: '***' });
        return r.json({ ok: true, note: '승인 토큰 검증 완료. 실제 재시도는 연결된 채널 업로드 구현 후 활성화됩니다.' });
    } catch (e) {
        return r.status(401).json({ ok: false, error: String(e.message || 'BAD_TOKEN') });
    }
});

// 초안 승인 엔드포인트 (승인 토큰 사용)
app.post('/organic/drafts/:id/approve', (q, r) => {
    try {
        const token = String((q.body || {}).token || '');
        const data = verify(token);
        const d = drafts.get(+q.params.id);
        if (!d || d.store_id !== q.storeId) return r.status(404).json({ ok: false });
        
        // 승인 토큰 검증 (단일 사용 보장 - P2에서 DB화)
        if (data.draft_id !== d.id) return r.status(403).json({ ok: false, error: 'BAD_TOKEN_TARGET' });
        
        // 승인된 채널 재시도
        const failedChannels = (d.results || []).filter(r => r.status === 'DRAFT_FALLBACK');
        if (failedChannels.length === 0) {
            return r.json({ ok: true, note: '모든 채널이 이미 발행되었습니다.' });
        }
        
        // 실제 재시도는 P2에서 구현
        d.history.push({ at: new Date().toISOString(), action: 'approve', token: '***', channels: failedChannels.map(c => c.channel) });
        d.status = 'APPROVED';
        
        return r.json({ ok: true, draft: d, note: '승인 토큰 검증 완료. 실제 재시도는 연결된 채널 업로드 구현 후 활성화됩니다.' });
    } catch (e) {
        return r.status(401).json({ ok: false, error: String(e.message || 'BAD_TOKEN') });
    }
});

// 인게스트(바디 제한 1MB), store_id 별 지출 합산
app.post('/ingest/:ch', express.json({ limit: '1mb' }), (q, r) => {
    const ch = String(q.params.ch || '').toUpperCase();
    const v = ingestSchema.safeParse(q.body);
    if (!v.success) return r.status(400).json({ ok: false });
    
    if (!metrics.byChannel[ch]) {
        metrics.byChannel[ch] = { impressions: 0, views: 0, clicks: 0, cost: 0, dm: 0, call: 0, route: 0, lead: 0 };
    }
    
    for (const x of v.data) {
        metrics.totals.impressions += x.impressions || 0;
        metrics.byChannel[ch].impressions += x.impressions || 0;
        metrics.totals.views += x.views || 0;
        metrics.byChannel[ch].views += x.views || 0;
        metrics.totals.clicks += x.clicks || 0;
        metrics.byChannel[ch].clicks += x.clicks || 0;
        metrics.totals.cost += x.cost || 0;
        metrics.byChannel[ch].cost += x.cost || 0;
        
        const c = x.conversions || {};
        for (const k of ['dm', 'call', 'route', 'lead']) {
            const vv = c[k] || 0;
            metrics.totals[k] += vv;
            metrics.byChannel[ch][k] = (metrics.byChannel[ch][k] || 0) + vv;
        }
        
        if (x.store_id) addSpend(x.store_id, x.cost || 0);
    }
    
    r.json({ ok: true, channel: ch, rows: v.data.length });
});

app.get('/metrics', (_q, r) => {
    r.json({
        ok: true,
        totals: metrics.totals,
        byChannel: metrics.byChannel,
        byStoreToday: Object.fromEntries(
            Object.entries(metrics.byStore).map(([k, v]) => [k, (v[todayStr()] || 0)])
        )
    });
});

// 인보이스 샘플 유지
app.post('/billing/checkout', (q, r) => {
    const { plan = 'Starter', price = 200000 } = q.body || {};
    const id = 'inv_' + (seqInv++);
    invoices.set(id, { plan, price, ts: new Date().toISOString() });
    r.json({ ok: true, invoice_id: id, pdf_url: `/billing/invoice/${id}/pdf` });
});

app.get('/billing/invoice/:id/pdf', (q, res) => {
    const pdf = "%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n4 0 obj\n<< /Length 94 >>\nstream\nBT\n/F1 18 Tf\n72 760 Td (INVOICE) Tj\n0 -30 Td (Plan: SAMPLE) Tj\n0 -30 Td (Amount: 200000 KRW) Tj\n0 -30 Td (Generated: 2025-11-11 UTC) Tj\nET\nendstream\nendobj\n5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\nxref\n0 6\n0000000000 65535 f \n0000000010 00000 n \n0000000061 00000 n \n0000000118 00000 n \n0000000302 00000 n \n0000000483 00000 n \ntrailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n580\n%%EOF";
    res.setHeader('Content-Type', 'application/pdf');
    res.send(Buffer.from(pdf));
});

const port = 5902;
app.listen(port, () => console.log('[petlink v2.7 P0-r1] listening :' + port));

