const express = require('express');
const cors = require('cors');
const app = express();

app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 8081;

// 플랜 조회 (v2.4.1)
app.get('/pricing/v2_4_1', (req, res) => {
    res.json({
        ok: true,
        plans: [
            {
                code: 'ALLIN_S',
                name: 'All-in S',
                total_price_monthly: 200000,
                ad_budget_cap: 120000,
                platform_fee: 80000,
                platforms: ['INSTAGRAM_FACEBOOK', 'TIKTOK']
            },
            {
                code: 'ALLIN_M',
                name: 'All-in M',
                total_price_monthly: 400000,
                ad_budget_cap: 300000,
                platform_fee: 100000,
                platforms: ['INSTAGRAM_FACEBOOK', 'TIKTOK']
            },
            {
                code: 'ALLIN_L',
                name: 'All-in L',
                total_price_monthly: 800000,
                ad_budget_cap: 600000,
                platform_fee: 200000,
                platforms: ['INSTAGRAM_FACEBOOK', 'TIKTOK']
            },
            {
                code: 'ALLIN_XL',
                name: 'All-in XL',
                total_price_monthly: 1500000,
                ad_budget_cap: 1100000,
                platform_fee: 400000,
                platforms: ['INSTAGRAM_FACEBOOK', 'TIKTOK']
            }
        ]
    });
});

// 플랜 전환
app.post('/subscriptions/switch-plan', (req, res) => {
    const { store_id, plan_code } = req.body;
    
    if (!store_id || !plan_code) {
        return res.status(400).json({
            ok: false,
            error: 'store_id와 plan_code가 필요합니다.'
        });
    }
    
    // 실제로는 구독 서비스와 연동
    res.json({
        ok: true,
        message: '플랜이 전환되었습니다.',
        data: {
            store_id,
            plan_code,
            switched_at: new Date().toISOString()
        }
    });
});

// 반경 설정 저장
app.put('/stores/:id/radius', (req, res) => {
    const storeId = parseInt(req.params.id);
    const { radius_km } = req.body;
    
    if (!radius_km || radius_km < 1 || radius_km > 20) {
        return res.status(400).json({
            ok: false,
            error: '반경은 1~20km 사이여야 합니다.'
        });
    }
    
    // 실제로는 DB에 저장
    res.json({
        ok: true,
        message: '반경이 설정되었습니다.',
        data: {
            store_id: storeId,
            radius_km
        }
    });
});

// 가중치 설정 저장
app.put('/stores/:id/weights', (req, res) => {
    const storeId = parseInt(req.params.id);
    const { mon, tue, wed, thu, fri, sat, sun, holiday, holidays_json } = req.body;
    
    // 실제로는 DB에 저장
    res.json({
        ok: true,
        message: '가중치가 설정되었습니다.',
        data: {
            store_id: storeId,
            weights: {
                mon: mon || 1.00,
                tue: tue || 1.00,
                wed: wed || 1.00,
                thu: thu || 1.05,
                fri: fri || 1.15,
                sat: sat || 1.30,
                sun: sun || 1.25,
                holiday: holiday || 1.30,
                holidays_json: holidays_json || []
            }
        }
    });
});

// 최근 7일 평균 CPM 조회
app.get('/stores/:id/cpm', (req, res) => {
    const storeId = parseInt(req.params.id);
    const { channel } = req.query;
    
    // 실제로는 channel_cpm_daily 테이블에서 최근 7일 평균 계산
    // 여기서는 Mock 데이터
    const mockCpm = {
        INSTAGRAM: 3000,
        FACEBOOK: 2800,
        TIKTOK: 3200,
        YOUTUBE: 2500,
        GOOGLE: 2200,
        KAKAO: 3500,
        NAVER: 3300
    };
    
    if (channel) {
        res.json({
            ok: true,
            data: {
                channel,
                avg_cpm_7d: mockCpm[channel] || 3000
            }
        });
    } else {
        res.json({
            ok: true,
            data: mockCpm
        });
    }
});

// 공휴일 설정 조회 (옵션)
app.get('/settings/holidays', (req, res) => {
    res.json({
        ok: true,
        holidays: ['2025-01-01', '2025-03-01', '2025-05-05', '2025-06-06', '2025-08-15', '2025-10-03', '2025-10-09', '2025-12-25']
    });
});

app.listen(PORT, () => {
    console.log(`mock exposure server :${PORT}`);
});

