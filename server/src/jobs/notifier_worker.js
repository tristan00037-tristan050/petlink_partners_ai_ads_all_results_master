const { pool } = require('../lib/db');
const cron = require('node-cron');
const { client } = require('../observability/metrics');

const counterSent = new client.Counter({ name:'notification_sent_total', help:'notifications marked sent' });

async function sendOne(row) {
  const to = process.env.NOTIFY_EMAIL_TO || null; // 운영에선 스토어 오너 이메일 조회로 확장
  console.log('[notify]', row.type, row.store_id, row.payload);
  
  if (to && process.env.SMTP_URL) {
    try {
      const { sendMail } = require('../lib/notifier/email');
      await sendMail({
        to, subject: `[알림] ${row.type}`,
        text: JSON.stringify(row.payload)
      });
    } catch (e) {
      console.error('[notify] email failed', e.message);
    }
  }
  
  await pool.query(`UPDATE notification_queue SET status='sent', sent_at=now() WHERE id=$1`, [row.id]);
  counterSent.inc();
}

async function runOnce() {
  const { rows } = await pool.query(
    `SELECT id, type, store_id, campaign_id, payload
     FROM notification_queue
     WHERE status='pending' AND scheduled_at <= now()
     ORDER BY id ASC LIMIT 50`
  );
  for (const r of rows) await sendOne(r);
}

function schedule(cronExpr='*/5 * * * *') { // 5분마다
  return cron.schedule(cronExpr, async () => { try { await runOnce(); } catch(e){ console.error(e); } });
}

module.exports = { runOnce, schedule };

