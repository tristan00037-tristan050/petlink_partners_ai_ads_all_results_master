// orchestrator.js - 채널 선택·반경·요일/공휴일 비중·Pacer

const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 8090;

app.use(cors());
app.use(express.json());

// 스토어 설정 저장소 (실제로는 DB)
const storeSettings = {};

// 채널 설정 API
app.put('/api/stores/:id/channel-prefs', (req, res) => {
    try {
        const storeId = parseInt(req.params.id);
        const { ig_enabled, tt_enabled, yt_enabled, kakao_enabled, naver_enabled } = req.body;
        
        if (!storeId) {
            return res.status(400).json({
                ok: false,
                error: 'store_id가 필요합니다.'
            });
        }
        
        // 최소 하나는 활성화되어야 함
        const enabledCount = [ig_enabled, tt_enabled, yt_enabled, kakao_enabled, naver_enabled]
            .filter(v => v === true).length;
        
        if (enabledCount === 0) {
            return res.status(400).json({
                ok: false,
                error: '최소 하나의 채널을 활성화해야 합니다.'
            });
        }
        
        if (!storeSettings[storeId]) {
            storeSettings[storeId] = {};
        }
        
        storeSettings[storeId].channel_prefs = {
            ig_enabled: ig_enabled === true,
            tt_enabled: tt_enabled === true,
            yt_enabled: yt_enabled === true,
            kakao_enabled: kakao_enabled === true,
            naver_enabled: naver_enabled === true
        };
        
        res.json({
            ok: true,
            message: '채널 설정이 저장되었습니다.',
            data: storeSettings[storeId].channel_prefs
        });
    } catch (error) {
        console.error('Channel prefs error:', error);
        res.status(500).json({
            ok: false,
            error: '채널 설정 저장 중 오류가 발생했습니다.'
        });
    }
});

app.get('/api/stores/:id/channel-prefs', (req, res) => {
    try {
        const storeId = parseInt(req.params.id);
        
        if (!storeSettings[storeId] || !storeSettings[storeId].channel_prefs) {
            // 기본값 반환
            return res.json({
                ok: true,
                data: {
                    ig_enabled: true,
                    tt_enabled: true,
                    yt_enabled: false,
                    kakao_enabled: false,
                    naver_enabled: false
                }
            });
        }
        
        res.json({
            ok: true,
            data: storeSettings[storeId].channel_prefs
        });
    } catch (error) {
        console.error('Channel prefs query error:', error);
        res.status(500).json({
            ok: false,
            error: '채널 설정 조회 중 오류가 발생했습니다.'
        });
    }
});

// 반경 설정 API
app.put('/api/stores/:id/radius', (req, res) => {
    try {
        const storeId = parseInt(req.params.id);
        const { radius_km } = req.body;
        
        if (!storeId || !radius_km || radius_km < 1 || radius_km > 20) {
            return res.status(400).json({
                ok: false,
                error: 'radius_km는 1~20 사이여야 합니다.'
            });
        }
        
        if (!storeSettings[storeId]) {
            storeSettings[storeId] = {};
        }
        
        storeSettings[storeId].radius_km = radius_km;
        
        res.json({
            ok: true,
            message: '반경 설정이 저장되었습니다.',
            data: { radius_km }
        });
    } catch (error) {
        console.error('Radius error:', error);
        res.status(500).json({
            ok: false,
            error: '반경 설정 저장 중 오류가 발생했습니다.'
        });
    }
});

app.get('/api/stores/:id/radius', (req, res) => {
    try {
        const storeId = parseInt(req.params.id);
        
        const radius = storeSettings[storeId]?.radius_km || 6; // 기본값 6km
        
        res.json({
            ok: true,
            data: { radius_km: radius }
        });
    } catch (error) {
        console.error('Radius query error:', error);
        res.status(500).json({
            ok: false,
            error: '반경 조회 중 오류가 발생했습니다.'
        });
    }
});

// 요일/공휴일 비중 설정 API
app.put('/api/stores/:id/weights', (req, res) => {
    try {
        const storeId = parseInt(req.params.id);
        const { mon, tue, wed, thu, fri, sat, sun, holiday } = req.body;
        
        if (!storeId) {
            return res.status(400).json({
                ok: false,
                error: 'store_id가 필요합니다.'
            });
        }
        
        if (!storeSettings[storeId]) {
            storeSettings[storeId] = {};
        }
        
        storeSettings[storeId].weights = {
            mon: mon || 1.00,
            tue: tue || 1.00,
            wed: wed || 1.00,
            thu: thu || 1.05,
            fri: fri || 1.15,
            sat: sat || 1.30,
            sun: sun || 1.25,
            holiday: holiday || 1.30
        };
        
        res.json({
            ok: true,
            message: '요일별 가중치가 저장되었습니다.',
            data: storeSettings[storeId].weights
        });
    } catch (error) {
        console.error('Weights error:', error);
        res.status(500).json({
            ok: false,
            error: '가중치 설정 저장 중 오류가 발생했습니다.'
        });
    }
});

app.get('/api/stores/:id/weights', (req, res) => {
    try {
        const storeId = parseInt(req.params.id);
        
        const weights = storeSettings[storeId]?.weights || {
            mon: 1.00,
            tue: 1.00,
            wed: 1.00,
            thu: 1.05,
            fri: 1.15,
            sat: 1.30,
            sun: 1.25,
            holiday: 1.30
        };
        
        res.json({
            ok: true,
            data: weights
        });
    } catch (error) {
        console.error('Weights query error:', error);
        res.status(500).json({
            ok: false,
            error: '가중치 조회 중 오류가 발생했습니다.'
        });
    }
});

// Pacer 적용 API (v2.6 r3)
app.post('/api/pacer/apply', (req, res) => {
    try {
        const { store_id, date, daily_budget } = req.body;
        
        if (!store_id || !date || !daily_budget) {
            return res.status(400).json({
                ok: false,
                error: 'store_id, date, daily_budget가 필요합니다.'
            });
        }
        
        const storeId = parseInt(store_id);
        const targetDate = new Date(date);
        const dayOfWeek = targetDate.getDay();
        const isHoliday = false; // 실제로는 공휴일 체크
        
        const weights = storeSettings[storeId]?.weights || {
            mon: 1.00, tue: 1.00, wed: 1.00, thu: 1.05,
            fri: 1.15, sat: 1.30, sun: 1.25, holiday: 1.30
        };
        
        const dayNames = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
        const dayKey = dayNames[dayOfWeek];
        const weight = isHoliday ? weights.holiday : weights[dayKey];
        
        const baseBudget = parseFloat(daily_budget);
        const adjustedBudget = baseBudget * weight;
        const cpm = 3000;
        const impressions = Math.floor(adjustedBudget / (cpm / 1000));
        const radius = storeSettings[storeId]?.radius_km || 6;
        
        // 실제로는 DB에 저장
        if (!storeSettings[storeId]) {
            storeSettings[storeId] = {};
        }
        if (!storeSettings[storeId].pacer) {
            storeSettings[storeId].pacer = {};
        }
        storeSettings[storeId].pacer[date] = {
            daily_budget: adjustedBudget,
            target: adjustedBudget,
            min: Math.round(adjustedBudget * 0.8),
            max: Math.round(adjustedBudget * 1.2),
            applied_at: new Date().toISOString()
        };
        
        res.json({
            ok: true,
            message: 'Pacer 설정이 적용되었습니다.',
            data: {
                date: date,
                day_of_week: dayKey,
                is_holiday: isHoliday,
                base_budget: baseBudget,
                weight: weight,
                adjusted_budget: Math.round(adjustedBudget),
                estimated_impressions: impressions,
                cpm: cpm,
                radius_km: radius,
                daily_pacing: {
                    min: Math.round(adjustedBudget * 0.8),
                    target: Math.round(adjustedBudget),
                    max: Math.round(adjustedBudget * 1.2)
                }
            }
        });
    } catch (error) {
        console.error('Pacer apply error:', error);
        res.status(500).json({
            ok: false,
            error: 'Pacer 적용 중 오류가 발생했습니다.'
        });
    }
});

// Engine Today API (v2.6 r3) - 일일 목표값 조회
app.get('/api/engine/today', (req, res) => {
    try {
        const { store_id, date } = req.query;
        
        if (!store_id) {
            return res.status(400).json({
                ok: false,
                error: 'store_id가 필요합니다.'
            });
        }
        
        const storeId = parseInt(store_id);
        const targetDate = date || new Date().toISOString().split('T')[0];
        
        // 실제로는 DB에서 조회
        const pacer = storeSettings[storeId]?.pacer?.[targetDate];
        
        if (!pacer) {
            // 기본값 반환
            const defaultBudget = 10000; // 예시
            return res.json({
                ok: true,
                data: {
                    date: targetDate,
                    target: defaultBudget,
                    min: Math.round(defaultBudget * 0.8),
                    max: Math.round(defaultBudget * 1.2),
                    current: 0, // 실제로는 집행량 조회
                    status: 'active'
                }
            });
        }
        
        res.json({
            ok: true,
            data: {
                date: targetDate,
                target: pacer.target,
                min: pacer.min,
                max: pacer.max,
                current: 0, // 실제로는 집행량 조회
                status: 'active'
            }
        });
    } catch (error) {
        console.error('Engine today error:', error);
        res.status(500).json({
            ok: false,
            error: '일일 목표값 조회 중 오류가 발생했습니다.'
        });
    }
});

// Pacer 프리뷰 API
app.get('/api/pacer/preview', (req, res) => {
    try {
        const { store_id, date, daily_budget } = req.query;
        
        if (!store_id || !date || !daily_budget) {
            return res.status(400).json({
                ok: false,
                error: 'store_id, date, daily_budget가 필요합니다.'
            });
        }
        
        const storeId = parseInt(store_id);
        const targetDate = new Date(date);
        const dayOfWeek = targetDate.getDay(); // 0=일, 1=월, ..., 6=토
        const isHoliday = false; // 실제로는 공휴일 체크
        
        const weights = storeSettings[storeId]?.weights || {
            mon: 1.00, tue: 1.00, wed: 1.00, thu: 1.05,
            fri: 1.15, sat: 1.30, sun: 1.25, holiday: 1.30
        };
        
        const dayNames = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
        const dayKey = dayNames[dayOfWeek];
        const weight = isHoliday ? weights.holiday : weights[dayKey];
        
        const baseBudget = parseFloat(daily_budget);
        const adjustedBudget = baseBudget * weight;
        
        // CPM 조회 (기본값: 3000)
        const cpm = 3000;
        const impressions = Math.floor(adjustedBudget / (cpm / 1000));
        
        // 반경 정보 포함
        const radius = storeSettings[storeId]?.radius_km || 6;
        
        res.json({
            ok: true,
            data: {
                date: date,
                day_of_week: dayKey,
                is_holiday: isHoliday,
                base_budget: baseBudget,
                weight: weight,
                adjusted_budget: Math.round(adjustedBudget),
                estimated_impressions: impressions,
                cpm: cpm,
                radius_km: radius,
                daily_pacing: {
                    min: Math.round(adjustedBudget * 0.8), // -20%
                    target: Math.round(adjustedBudget),
                    max: Math.round(adjustedBudget * 1.2)  // +20%
                }
            }
        });
    } catch (error) {
        console.error('Pacer preview error:', error);
        res.status(500).json({
            ok: false,
            error: 'Pacer 프리뷰 생성 중 오류가 발생했습니다.'
        });
    }
});

// CPM 조회 API (v2.6 r3)
app.get('/api/stores/:id/cpm', (req, res) => {
    try {
        const storeId = parseInt(req.params.id);
        
        // 모의 CPM 데이터 (실제로는 채널별로 다를 수 있음)
        const cpm = {
            instagram: 3000,
            facebook: 2800,
            tiktok: 3200,
            youtube: 2500,
            kakao: 3500,
            naver: 4000,
            average: 3000
        };
        
        res.json({
            ok: true,
            data: {
                store_id: storeId,
                cpm: cpm,
                last_updated: new Date().toISOString()
            }
        });
    } catch (error) {
        console.error('CPM query error:', error);
        res.status(500).json({
            ok: false,
            error: 'CPM 조회 중 오류가 발생했습니다.'
        });
    }
});

// Ingest API (v2.6 r3) - 리포팅 수집
app.post('/api/ingest/:channel', (req, res) => {
    try {
        const channel = req.params.channel.toUpperCase();
        const { store_id, metrics } = req.body;
        
        if (!store_id || !metrics) {
            return res.status(400).json({
                ok: false,
                error: 'store_id와 metrics가 필요합니다.'
            });
        }
        
        // 지원 채널 확인
        const supportedChannels = ['META', 'TIKTOK', 'YOUTUBE', 'KAKAO', 'NAVER'];
        if (!supportedChannels.includes(channel)) {
            return res.status(400).json({
                ok: false,
                error: `지원하지 않는 채널입니다. 지원 채널: ${supportedChannels.join(', ')}`
            });
        }
        
        // 실제로는 DB에 저장
        const storeId = parseInt(store_id);
        if (!storeSettings[storeId]) {
            storeSettings[storeId] = {};
        }
        if (!storeSettings[storeId].metrics) {
            storeSettings[storeId].metrics = {};
        }
        if (!storeSettings[storeId].metrics[channel]) {
            storeSettings[storeId].metrics[channel] = [];
        }
        
        storeSettings[storeId].metrics[channel].push({
            ...metrics,
            channel: channel,
            collected_at: new Date().toISOString()
        });
        
        res.json({
            ok: true,
            message: `${channel} 메트릭이 수집되었습니다.`,
            data: {
                channel: channel,
                store_id: storeId,
                metrics: metrics
            }
        });
    } catch (error) {
        console.error('Ingest error:', error);
        res.status(500).json({
            ok: false,
            error: '메트릭 수집 중 오류가 발생했습니다.'
        });
    }
});

// Metrics 조회 API (v2.6 r3) - 대시보드용 합산
app.get('/api/metrics', (req, res) => {
    try {
        const { store_id, start_date, end_date } = req.query;
        
        if (!store_id) {
            return res.status(400).json({
                ok: false,
                error: 'store_id가 필요합니다.'
            });
        }
        
        const storeId = parseInt(store_id);
        const metrics = storeSettings[storeId]?.metrics || {};
        
        // 채널별 합산
        const aggregated = {
            total_impressions: 0,
            total_clicks: 0,
            total_spend: 0,
            total_messages: 0,
            total_leads: 0,
            by_channel: {}
        };
        
        Object.keys(metrics).forEach(channel => {
            const channelMetrics = metrics[channel] || [];
            const channelTotal = channelMetrics.reduce((acc, m) => {
                acc.impressions += m.impressions || 0;
                acc.clicks += m.clicks || 0;
                acc.spend += m.spend || 0;
                acc.messages += m.messages || 0;
                acc.leads += m.leads || 0;
                return acc;
            }, { impressions: 0, clicks: 0, spend: 0, messages: 0, leads: 0 });
            
            aggregated.by_channel[channel] = {
                ...channelTotal,
                cpm: channelTotal.impressions > 0 ? (channelTotal.spend / channelTotal.impressions) * 1000 : 0,
                cpc: channelTotal.clicks > 0 ? channelTotal.spend / channelTotal.clicks : 0,
                cpa: channelTotal.leads > 0 ? channelTotal.spend / channelTotal.leads : 0
            };
            
            aggregated.total_impressions += channelTotal.impressions;
            aggregated.total_clicks += channelTotal.clicks;
            aggregated.total_spend += channelTotal.spend;
            aggregated.total_messages += channelTotal.messages;
            aggregated.total_leads += channelTotal.leads;
        });
        
        aggregated.overall_cpm = aggregated.total_impressions > 0 ? (aggregated.total_spend / aggregated.total_impressions) * 1000 : 0;
        aggregated.overall_cpc = aggregated.total_clicks > 0 ? aggregated.total_spend / aggregated.total_clicks : 0;
        aggregated.overall_cpa = aggregated.total_leads > 0 ? aggregated.total_spend / aggregated.total_leads : 0;
        
        res.json({
            ok: true,
            data: {
                store_id: storeId,
                period: {
                    start: start_date || null,
                    end: end_date || null
                },
                metrics: aggregated
            }
        });
    } catch (error) {
        console.error('Metrics query error:', error);
        res.status(500).json({
            ok: false,
            error: '메트릭 조회 중 오류가 발생했습니다.'
        });
    }
});

// 공휴일 조회 API (v2.6 r3)
app.get('/api/settings/holidays', (req, res) => {
    try {
        // 모의 공휴일 데이터 (실제로는 DB 또는 외부 API에서 조회)
        const holidays = [
            { date: '2025-01-01', name: '신정' },
            { date: '2025-03-01', name: '삼일절' },
            { date: '2025-05-05', name: '어린이날' },
            { date: '2025-06-06', name: '현충일' },
            { date: '2025-08-15', name: '광복절' },
            { date: '2025-10-03', name: '개천절' },
            { date: '2025-10-09', name: '한글날' },
            { date: '2025-12-25', name: '크리스마스' }
        ];
        
        res.json({
            ok: true,
            data: {
                holidays: holidays,
                year: new Date().getFullYear()
            }
        });
    } catch (error) {
        console.error('Holidays query error:', error);
        res.status(500).json({
            ok: false,
            error: '공휴일 조회 중 오류가 발생했습니다.'
        });
    }
});

// Health check
app.get('/healthz', (req, res) => {
    res.json({ 
        ok: true, 
        service: 'orchestrator', 
        port: PORT,
        version: 'v2.6-r3',
        endpoints: [
            'PUT/GET /api/stores/:id/channel-prefs',
            'PUT/GET /api/stores/:id/radius',
            'PUT/GET /api/stores/:id/weights',
            'GET /api/stores/:id/cpm',
            'GET /api/pacer/preview',
            'POST /api/pacer/apply',
            'GET /api/engine/today',
            'POST /api/ingest/:channel',
            'GET /api/metrics',
            'GET /api/settings/holidays'
        ]
    });
});

app.listen(PORT, () => {
    console.log(`Orchestrator server running on port ${PORT} (v2.6-r3)`);
    console.log(`Endpoints:`);
    console.log(`  PUT/GET /api/stores/:id/channel-prefs`);
    console.log(`  PUT/GET /api/stores/:id/radius`);
    console.log(`  PUT/GET /api/stores/:id/weights`);
    console.log(`  GET /api/stores/:id/cpm`);
    console.log(`  GET /api/pacer/preview`);
    console.log(`  GET /api/settings/holidays`);
});

