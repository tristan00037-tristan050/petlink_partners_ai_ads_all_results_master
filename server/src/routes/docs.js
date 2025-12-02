const express = require('express');
const swaggerUi = require('swagger-ui-express');

const router = express.Router();

function gateDocs(req, res, next) {
  const protect = String(process.env.DOCS_PROTECT || 'false') === 'true';
  const isProd = process.env.NODE_ENV === 'production';
  if (protect && isProd) {
    const key = req.headers['x-admin-key'] || '';
    if (!key || key !== process.env.ADMIN_API_KEY) {
      return res.status(403).send('Forbidden');
    }
  }
  next();
}

const spec = {
  openapi: '3.0.0',
  info: { title: 'P0 API', version: '1.0.0' },
  servers: [{ url: process.env.API_BASE_URL || 'http://localhost:5903' }],
  paths: {
    '/auth/login': { post: { summary: '로그인' } },
    '/auth/signup': { post: { summary: '회원가입' } },
    '/auth/me': { get: { summary: '내 정보 조회' } },
    '/plans': { get: { summary: '요금제 조회' } },
    '/stores': { get: { summary: '내 매장 목록' }, post: { summary: '매장 생성' } },
    '/stores/{id}/subscribe': { post: { summary: '구독 생성' }, parameters:[{name:'id',in:'path'}] },
    '/stores/{id}/pets': { get: { summary: '반려동물 목록' }, post: { summary: '반려동물 등록' }, parameters:[{name:'id',in:'path'}] },
    '/stores/{id}/campaigns': { get: { summary: '캠페인 목록' }, post: { summary: '캠페인 생성' }, parameters:[{name:'id',in:'path'}] },
    '/campaigns/{cid}/activate': { post: { summary: '캠페인 활성화' }, parameters:[{name:'cid',in:'path'}] },
    '/campaigns/{cid}/pause': { post: { summary: '캠페인 일시중지' }, parameters:[{name:'cid',in:'path'}] },
    '/campaigns/{cid}/stop': { post: { summary: '캠페인 중지' }, parameters:[{name:'cid',in:'path'}] },
    '/pg/webhook/{provider}': { post: { summary: 'PG Webhook 수신' }, parameters:[{name:'provider',in:'path'}] },
    '/admin/policy/campaigns/{cid}/resolve': { post: { summary: '정책 해제' }, parameters:[{name:'cid',in:'path'}] },
    '/admin/ops/scheduler/run': { post: { summary: '스케줄러 수동 실행' } },
    '/admin/reports/summary': { get: { summary: '운영 요약 리포트' } },
    '/admin/reports/billing': { get: { summary: '빌링 리포트' } },
    '/meta/status-map': { get: { summary: '상태 라벨 맵' } }
  }
};

router.get('/docs.json', gateDocs, (_req, res) => {
  res.json(spec);
});

router.use('/docs', gateDocs, swaggerUi.serve, swaggerUi.setup(spec));
module.exports = router;

