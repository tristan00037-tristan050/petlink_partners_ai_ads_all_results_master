// mock_api.js - 스테이징용 API (plan switch / invoice)

const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 5800;

app.use(cors());
app.use(express.json());

// 플랜 정보
const plans = {
    'STARTER': {
        name: 'Starter',
        price: 200000,
        ad_amount: 120000
    },
    'STANDARD': {
        name: 'Standard',
        price: 400000,
        ad_amount: 300000
    },
    'PRO': {
        name: 'Pro',
        price: 800000,
        ad_amount: 600000
    }
};

// 플랜 전환 API
app.post('/api/plan/switch', (req, res) => {
    try {
        const { store_id, plan_code } = req.body;
        
        if (!store_id || !plan_code) {
            return res.status(400).json({
                ok: false,
                error: 'store_id와 plan_code가 필요합니다.'
            });
        }
        
        const plan = plans[plan_code.toUpperCase()];
        if (!plan) {
            return res.status(400).json({
                ok: false,
                error: '유효하지 않은 플랜 코드입니다.'
            });
        }
        
        // 인보이스 ID 생성 (실제로는 DB에서 생성)
        const invoiceId = Date.now();
        const invoiceNumber = `INV-2025-${String(invoiceId).slice(-6)}`;
        
        res.json({
            ok: true,
            message: '플랜이 전환되었습니다.',
            data: {
                plan_code: plan_code.toUpperCase(),
                plan_name: plan.name,
                invoice_id: invoiceId,
                invoice_number: invoiceNumber
            }
        });
    } catch (error) {
        console.error('Plan switch error:', error);
        res.status(500).json({
            ok: false,
            error: '플랜 전환 중 오류가 발생했습니다.'
        });
    }
});

// 인보이스 조회 API
app.get('/api/invoice/:id', (req, res) => {
    try {
        const invoiceId = req.params.id;
        
        // 모의 인보이스 데이터
        const invoice = {
            invoice_id: invoiceId,
            invoice_number: `INV-2025-${String(invoiceId).slice(-6)}`,
            store_id: 1,
            store_name: '강남 펫샵',
            billing_date: new Date().toLocaleDateString('ko-KR'),
            plan_code: 'STARTER',
            plan_name: 'Starter',
            plan_amount: 200000,
            ad_amount: 120000,
            total_amount: 200000,
            items: [
                {
                    name: '플랜 요금 (Starter)',
                    description: '플랜 요금 (Starter)',
                    amount: 200000
                },
                {
                    name: '포함 광고비',
                    description: '포함 광고비',
                    amount: 120000
                }
            ]
        };
        
        res.json({
            ok: true,
            data: invoice
        });
    } catch (error) {
        console.error('Invoice fetch error:', error);
        res.status(500).json({
            ok: false,
            error: '인보이스 조회 중 오류가 발생했습니다.'
        });
    }
});

// Health check
app.get('/healthz', (req, res) => {
    res.json({ ok: true, service: 'mock_api', port: PORT });
});

app.listen(PORT, () => {
    console.log(`Mock API server running on port ${PORT}`);
    console.log(`Endpoints:`);
    console.log(`  POST /api/plan/switch`);
    console.log(`  GET /api/invoice/:id`);
});


