const express = require('express');
const router = express.Router();

router.get('/meta/status-map', (_req, res) => {
  res.json({
    ok: true,
    campaign: {
      draft:   { label: '초안',        user_actions: ['activate','delete'], admin_actions: ['delete'] },
      active:  { label: '집행중',      user_actions: ['pause','stop'],      admin_actions: ['stop'] },
      paused:  { label: '일시중지',    user_actions: ['activate','stop'],   admin_actions: ['stop'] },
      stopped: { label: '종료',        user_actions: [],                    admin_actions: [] }
    },
    blocked: {
      policy:  { code: 'BLOCKED_BY_POLICY',  user_hint: '정책 위반 요소를 수정하거나 관리 승인 요청이 필요합니다.' },
      billing: { code: 'BLOCKED_BY_BILLING', user_hint: '연체 해소(결제 완료) 후 재시도하세요.' }
    }
  });
});

module.exports = router;

