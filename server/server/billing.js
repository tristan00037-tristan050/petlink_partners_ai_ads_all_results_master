// billing.js - 플랜 전환·인보이스 PDF

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 8091;

app.use(cors());
app.use(express.json());

// PDF 디렉토리
const PDF_DIR = path.join(__dirname, 'pdf');
if (!fs.existsSync(PDF_DIR)) {
    fs.mkdirSync(PDF_DIR, { recursive: true });
}

// 플랜 정보
const plans = {
    'STARTER': {
        name: 'Starter',
        price: 200000,
        ad_amount: 120000,
        tech_fee: 80000
    },
    'STANDARD': {
        name: 'Standard',
        price: 400000,
        ad_amount: 300000,
        tech_fee: 100000
    },
    'PRO': {
        name: 'Pro',
        price: 800000,
        ad_amount: 600000,
        tech_fee: 200000
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
        
        // 인보이스 ID 생성
        const invoiceId = Date.now();
        const invoiceNumber = `INV-2025-${String(invoiceId).slice(-6)}`;
        
        // 인보이스 데이터 생성
        const invoice = {
            invoice_id: invoiceId,
            invoice_number: invoiceNumber,
            store_id: store_id,
            store_name: '강남 펫샵', // 실제로는 DB에서 조회
            billing_date: new Date().toLocaleDateString('ko-KR'),
            billing_period: {
                start: new Date(new Date().getFullYear(), new Date().getMonth(), 1).toLocaleDateString('ko-KR'),
                end: new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).toLocaleDateString('ko-KR')
            },
            plan_code: plan_code.toUpperCase(),
            plan_name: plan.name,
            plan_amount: plan.price,
            ad_amount: plan.ad_amount,
            tech_fee: plan.tech_fee,
            subtotal: plan.price,
            vat: Math.floor(plan.price * 0.1), // 부가세 10%
            total_amount: Math.floor(plan.price * 1.1), // 총액 (부가세 포함)
            items: [
                {
                    name: `플랜 요금 (${plan.name})`,
                    description: `플랜 요금 (${plan.name})`,
                    amount: plan.price,
                    quantity: 1,
                    unit_price: plan.price
                }
            ],
            payment_due_date: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toLocaleDateString('ko-KR'), // 7일 후
            status: 'pending'
        };
        
        res.json({
            ok: true,
            message: '플랜이 전환되었습니다.',
            data: {
                plan_code: plan_code.toUpperCase(),
                plan_name: plan.name,
                invoice_id: invoiceId,
                invoice_number: invoiceNumber,
                invoice: invoice
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
        const plan = plans['STARTER'] || plans['STARTER'];
        const invoice = {
            invoice_id: invoiceId,
            invoice_number: `INV-2025-${String(invoiceId).slice(-6)}`,
            store_id: 1,
            store_name: '강남 펫샵',
            billing_date: new Date().toLocaleDateString('ko-KR'),
            billing_period: {
                start: new Date(new Date().getFullYear(), new Date().getMonth(), 1).toLocaleDateString('ko-KR'),
                end: new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).toLocaleDateString('ko-KR')
            },
            plan_code: 'STARTER',
            plan_name: 'Starter',
            plan_amount: plan.price,
            ad_amount: plan.ad_amount,
            tech_fee: plan.tech_fee,
            subtotal: plan.price,
            vat: Math.floor(plan.price * 0.1),
            total_amount: Math.floor(plan.price * 1.1),
            items: [
                {
                    name: `플랜 요금 (${plan.name})`,
                    description: `플랜 요금 (${plan.name})`,
                    amount: plan.price,
                    quantity: 1,
                    unit_price: plan.price
                }
            ],
            payment_due_date: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toLocaleDateString('ko-KR'),
            status: 'pending'
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

// 인보이스 PDF 생성 API
app.get('/api/invoice/:id/pdf', (req, res) => {
    try {
        const invoiceId = req.params.id;
        const pdfPath = path.join(PDF_DIR, `invoice_${invoiceId}.pdf`);
        
        // 샘플 PDF가 있으면 반환, 없으면 404
        if (fs.existsSync(pdfPath)) {
            res.setHeader('Content-Type', 'application/pdf');
            res.setHeader('Content-Disposition', `attachment; filename="invoice_${invoiceId}.pdf"`);
            res.sendFile(pdfPath);
        } else {
            // 샘플 PDF 반환
            const samplePath = path.join(PDF_DIR, 'invoice_sample.pdf');
            if (fs.existsSync(samplePath)) {
                res.setHeader('Content-Type', 'application/pdf');
                res.setHeader('Content-Disposition', `attachment; filename="invoice_${invoiceId}.pdf"`);
                res.sendFile(samplePath);
            } else {
                res.status(404).json({
                    ok: false,
                    error: 'PDF 파일을 찾을 수 없습니다.'
                });
            }
        }
    } catch (error) {
        console.error('PDF generation error:', error);
        res.status(500).json({
            ok: false,
            error: 'PDF 생성 중 오류가 발생했습니다.'
        });
    }
});

// 플랜 목록 조회 API (v2.6 r3)
app.get('/api/plans', (req, res) => {
    try {
        const planList = Object.keys(plans).map(code => ({
            code: code,
            name: plans[code].name,
            price: plans[code].price,
            ad_amount: plans[code].ad_amount,
            tech_fee: plans[code].tech_fee,
            total_with_vat: Math.floor(plans[code].price * 1.1)
        }));
        
        res.json({
            ok: true,
            data: {
                plans: planList,
                currency: 'KRW',
                vat_rate: 0.1
            }
        });
    } catch (error) {
        console.error('Plans query error:', error);
        res.status(500).json({
            ok: false,
            error: '플랜 목록 조회 중 오류가 발생했습니다.'
        });
    }
});

// Health check
app.get('/healthz', (req, res) => {
    res.json({ 
        ok: true, 
        service: 'billing', 
        port: PORT,
        version: 'v2.6-r3',
        endpoints: [
            'GET /api/plans',
            'POST /api/plan/switch',
            'GET /api/invoice/:id',
            'GET /api/invoice/:id/pdf'
        ]
    });
});

app.listen(PORT, () => {
    console.log(`Billing server running on port ${PORT} (v2.6-r3)`);
    console.log(`Endpoints:`);
    console.log(`  GET /api/plans`);
    console.log(`  POST /api/plan/switch`);
    console.log(`  GET /api/invoice/:id`);
    console.log(`  GET /api/invoice/:id/pdf`);
});

