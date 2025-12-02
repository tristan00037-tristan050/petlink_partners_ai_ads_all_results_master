// 알림 유틸리티 (웹훅 또는 콘솔 로그)
const webhookUrl = process.env.ADMIN_ALERT_WEBHOOK_URL || '';

async function notify(type, data) {
  if (webhookUrl) {
    try {
      const { fetch } = require('undici') || globalThis.fetch;
      await fetch(webhookUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ type, data, ts: new Date().toISOString() })
      });
    } catch (e) {
      console.warn('[alerts] webhook failed:', e.message);
    }
  } else {
    console.log(`[ALERT] ${type}:`, JSON.stringify(data, null, 2));
  }
  return { ok: true };
}

module.exports = { notify };
