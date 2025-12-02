/**
 * 클라이언트 개발용 Mock API 서버
 * 서버 없이 클라이언트 개발을 위한 간단한 Mock 서버
 * 
 * 실행 방법:
 *   node server/mock_api_client_dev.js
 * 
 * 포트: 5902 (기본 서버와 동일)
 */

const express = require('express');
const cors = require('cors');
const app = express();
const PORT = process.env.PORT || 5902;

// CORS 설정
app.use(cors({
    origin: ['http://localhost:8000', 'http://localhost:3000', 'http://localhost:5902'],
    credentials: true
}));

app.use(express.json({ limit: '10mb' }));

// Mock 데이터 저장소 (메모리)
const mockData = {
    stores: new Map(),
    animals: new Map(),
    drafts: new Map(),
    invoices: new Map(),
    channelPrefs: new Map(),
    subscriptions: new Map(),
    metrics: {
        totals: { impressions: 0, views: 0, clicks: 0, cost: 0 },
        byChannel: {},
        byStore: {}
    }
};

// ============================================
// 인증 관련
// ============================================

app.post('/auth/signup', (req, res) => {
    const { email, password } = req.body;
    const token = `mock-token-${Date.now()}`;
    res.json({ ok: true, token, user: { id: 1, email } });
});

app.post('/auth/login', (req, res) => {
    const { email, password } = req.body;
    const token = `mock-token-${Date.now()}`;
    res.json({ ok: true, token, user: { id: 1, email } });
});

// ============================================
// 스토어 관련
// ============================================

app.get('/stores/:id/channel-prefs', (req, res) => {
    const storeId = req.params.id;
    const prefs = mockData.channelPrefs.get(storeId) || {
        ig_enabled: true,
        tt_enabled: true,
        yt_enabled: false,
        kakao_enabled: false,
        naver_enabled: false
    };
    res.json({ ok: true, prefs });
});

app.put('/stores/:id/channel-prefs', (req, res) => {
    const storeId = req.params.id;
    mockData.channelPrefs.set(storeId, req.body);
    res.json({ ok: true, prefs: req.body });
});

app.get('/stores/:id/radius', (req, res) => {
    res.json({ ok: true, radius_km: 6 });
});

app.put('/stores/:id/radius', (req, res) => {
    res.json({ ok: true, radius_km: req.body.radius_km || 6 });
});

app.get('/stores/:id/weights', (req, res) => {
    res.json({ ok: true, weights: {
        mon: 1, tue: 1, wed: 1, thu: 1.05,
        fri: 1.15, sat: 1.30, sun: 1.25,
        holiday: 1.30, holidays: []
    }});
});

app.put('/stores/:id/weights', (req, res) => {
    res.json({ ok: true, weights: req.body.weights });
});

// ============================================
// 동물 관련
// ============================================

app.post('/animals', (req, res) => {
    const animalId = Date.now();
    const animal = { id: animalId, ...req.body, created_at: new Date().toISOString() };
    mockData.animals.set(animalId, animal);
    res.status(201).json({ ok: true, animal_id: animalId, scheduled: ['META', 'TIKTOK'] });
});

app.get('/animals', (req, res) => {
    const animals = Array.from(mockData.animals.values());
    res.json({ ok: true, items: animals });
});

app.put('/animals/:id/channel-overrides', (req, res) => {
    res.json({ ok: true, message: '채널 오버라이드 저장됨' });
});

// ============================================
// 초안 관련
// ============================================

app.post('/organic/drafts', (req, res) => {
    const draftId = Date.now();
    const draft = { id: draftId, ...req.body, status: 'DRAFT', created_at: new Date().toISOString() };
    mockData.drafts.set(draftId, draft);
    res.status(201).json({ ok: true, draft_id: draftId });
});

app.get('/organic/drafts', (req, res) => {
    const drafts = Array.from(mockData.drafts.values());
    res.json({ ok: true, items: drafts });
});

app.post('/organic/drafts/:id/publish', (req, res) => {
    const draft = mockData.drafts.get(parseInt(req.params.id));
    if (!draft) return res.status(404).json({ ok: false, error: 'Draft not found' });
    draft.status = 'PUBLISHED';
    draft.published_at = new Date().toISOString();
    res.json({ ok: true, draft });
});

// ============================================
// 요금제 관련
// ============================================

app.get('/api/plans', (req, res) => {
    res.json({ ok: true, plans: [
        { code: 'ALLIN_S', name: 'All-in S', price: 200000, ad_spend: 120000 },
        { code: 'ALLIN_M', name: 'All-in M', price: 400000, ad_spend: 300000 },
        { code: 'ALLIN_L', name: 'All-in L', price: 800000, ad_spend: 600000 },
        { code: 'ALLIN_XL', name: 'All-in XL', price: 1500000, ad_spend: 1100000 }
    ]});
});

app.post('/api/plan/switch', (req, res) => {
    const invoiceId = `inv_${Date.now()}`;
    res.json({ ok: true, invoice_id: invoiceId, message: '플랜 전환 완료' });
});

// ============================================
// 인보이스 관련
// ============================================

app.get('/api/invoice/:id', (req, res) => {
    const invoice = mockData.invoices.get(req.params.id) || {
        id: req.params.id,
        store_id: 1,
        plan: 'ALLIN_S',
        subtotal: 200000,
        vat: 20000,
        total: 220000,
        billing_period: { start: '2025-11-01', end: '2025-11-30' },
        due_date: '2025-12-05',
        status: 'PENDING'
    };
    res.json({ ok: true, invoice });
});

app.get('/api/invoice/:id/pdf', (req, res) => {
    res.json({ ok: true, pdf_url: `/api/invoice/${req.params.id}/pdf` });
});

// ============================================
// 메트릭 관련
// ============================================

app.get('/metrics', (req, res) => {
    res.json({ ok: true, aggregated: {
        total_impressions: 12345,
        total_clicks: 567,
        total_views: 890,
        platform_breakdown: {
            facebook_instagram: { impressions: 8000, clicks: 400 },
            tiktok: { impressions: 4345, clicks: 167 }
        },
        age_breakdown: { '20-29': 4000, '30-39': 5000, '40-49': 3345 },
        gender_breakdown: { female: 7000, male: 5345 },
        region_breakdown: { '서울': 5000, '경기': 4000, '인천': 3345 }
    }});
});

app.get('/metrics/daily', (req, res) => {
    const days = parseInt(req.query.days || '7', 10);
    const daily = [];
    for (let i = 0; i < days; i++) {
        const date = new Date();
        date.setDate(date.getDate() - i);
        daily.push({
            date: date.toISOString().split('T')[0],
            impressions: Math.floor(Math.random() * 1000) + 500,
            clicks: Math.floor(Math.random() * 50) + 20,
            cost: Math.floor(Math.random() * 50000) + 20000
        });
    }
    res.json({ ok: true, daily: daily.reverse() });
});

// ============================================
// Orchestrator 관련 (8090 포트)
// ============================================

app.get('/api/stores/:id/cpm', (req, res) => {
    res.json({ ok: true, cpm: {
        META: 5000,
        TIKTOK: 4500,
        YOUTUBE: 6000,
        KAKAO: 4000,
        NAVER: 5500
    }});
});

app.get('/api/settings/holidays', (req, res) => {
    res.json({ ok: true, holidays: [
        '2025-01-01', '2025-03-01', '2025-05-05',
        '2025-06-06', '2025-08-15', '2025-10-03',
        '2025-10-09', '2025-12-25'
    ]});
});

app.get('/api/pacer/preview', (req, res) => {
    res.json({ ok: true, schedule: [
        { date: '2025-11-12', amount: 1000, min: 800, max: 1200 },
        { date: '2025-11-13', amount: 1200, min: 960, max: 1440 }
    ]});
});

// ============================================
// Billing 관련 (8091 포트)
// ============================================

// 이미 위에 정의됨 (/api/plan/switch, /api/invoice/:id)

// ============================================
// Health Check
// ============================================

app.get('/health', (req, res) => {
    res.json({ ok: true, service: 'mock-api-client-dev', version: '1.0.0' });
});

// ============================================
// 서버 시작
// ============================================

app.listen(PORT, () => {
    console.log(`[Mock API Client Dev] 서버 실행 중: http://localhost:${PORT}`);
    console.log(`[Mock API Client Dev] 클라이언트 개발용 Mock API 서버`);
    console.log(`[Mock API Client Dev] 모든 엔드포인트가 Mock 데이터를 반환합니다.`);
});


