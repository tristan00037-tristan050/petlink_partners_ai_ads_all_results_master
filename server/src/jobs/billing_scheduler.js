const { pool } = require('../lib/db');
const cron = require('node-cron');
const { client } = require('../observability/metrics');

const counterRun   = new client.Counter({ name:'billing_scheduler_runs_total', help:'billing scheduler runs' });
const counterPaused= new client.Counter({ name:'billing_scheduler_paused_campaigns_total', help:'campaigns paused by billing' });
const counterNotif = new client.Counter({ name:'notification_enqueued_total', help:'notifications enqueued' });

function nowTs() {
  const override = process.env.SCHEDULER_NOW_TS;
  return override ? new Date(override) : new Date();
}

async function enqueue(type, storeId, when, payload) {
  await pool.query(
    `INSERT INTO notification_queue(type, store_id, scheduled_at, payload, status)
     VALUES ($1,$2,$3,$4,'pending')
     ON CONFLICT (type, store_id, scheduled_at) DO NOTHING`,
    [type, storeId, when, JSON.stringify(payload || {})]
  );
  counterNotif.inc();
}

async function coreRun() {
  const grace = parseInt(process.env.BILLING_GRACE_DAYS || '1', 10);

  // 1) 연체 처리
  await pool.query(
    `UPDATE invoices SET status='overdue'
     WHERE status='pending' AND due_date < now() - ($1 || ' day')::interval`,
    [String(grace)]
  );

  // 2) 캠페인 자동 일시중지
  const upd = await pool.query(
    `UPDATE campaigns c SET status='paused'
     FROM invoices i
     WHERE i.store_id=c.store_id AND i.status='overdue' AND c.status='active'
     RETURNING c.id`
  );
  counterPaused.inc(upd.rows.length);
  for (const r of upd.rows) {
    await pool.query(
      `INSERT INTO campaign_status_history (campaign_id, from_status, to_status, reason_code, note)
       VALUES ($1,'active','paused','blocked_by_billing','auto-scheduler')`,
      [r.id]
    );
  }

  // 3) 청구 알림 스케줄링(D-2/D-1/D0/D+1)
  const t = nowTs();
  const { rows: subs } = await pool.query(
    `SELECT sps.store_id, sps.period_end
     FROM store_plan_subscriptions sps
     WHERE sps.status='active' AND now() BETWEEN sps.period_start AND sps.period_end`
  );
  for (const s of subs) {
    const end = new Date(s.period_end);
    const d2  = new Date(end); d2.setDate(end.getDate()-2);
    const d1  = new Date(end); d1.setDate(end.getDate()-1);
    const d0  = end;
    const dp1 = new Date(end); dp1.setDate(end.getDate()+1);
    // 미래 시각만 큐에 넣음(중복 방지를 위해 동일 (type,store,scheduled_at) 유일성은 DB로도 고려 가능)
    if (d2 > t) await enqueue('billing_due_d2',  s.store_id, d2,  { msg:'결제 2일 전' });
    if (d1 > t) await enqueue('billing_due_d1',  s.store_id, d1,  { msg:'결제 1일 전' });
    if (d0 > t) await enqueue('billing_due',     s.store_id, d0,  { msg:'결제일' });
    if (dp1> t) await enqueue('billing_overdue_d1', s.store_id, dp1,{ msg:'미납 D+1' });
  }
}

async function runOnce() {
  counterRun.inc();
  await coreRun();
  return true;
}

// 운영 크론 예: 매일 00:05 KST
function schedule(cronExpr='5 0 * * *') {
  return cron.schedule(cronExpr, async () => { try { await runOnce(); } catch (e) { console.error(e); } });
}

module.exports = { runOnce, schedule };
