/**
 * P0: BillingScheduler
 * 월 결제 상태 기반 제어 (D-2/D-1/D 알림, D+1 미납 자동 정지/재개)
 */

const db = require('../lib/db');
const cron = require('node-cron');

/**
 * D-2/D-1/D 예정 알림
 */
async function sendBillingReminders() {
  try {
    const today = new Date();
    const d2 = new Date(today);
    d2.setDate(today.getDate() + 2);
    const d1 = new Date(today);
    d1.setDate(today.getDate() + 1);

    // D-2, D-1, D (오늘) 결제 예정 구독 조회
    const subscriptions = await db.q(`
      SELECT s.*, st.name as store_name, u.email
      FROM store_plan_subscriptions s
      JOIN stores st ON s.store_id = st.id
      JOIN users u ON st.user_id = u.id
      WHERE s.status = 'ACTIVE'
        AND s.next_billing_date IN ($1, $2, $3)
    `, [
      today.toISOString().split('T')[0],
      d1.toISOString().split('T')[0],
      d2.toISOString().split('T')[0]
    ]);

    for (const sub of subscriptions.rows) {
      // TODO: 실제 알림 발송 (이메일, 내부 알림 등)
      console.log(`[Billing Reminder] Store: ${sub.store_name}, Next billing: ${sub.next_billing_date}`);
      
      // 내부 알림 기록 (예시)
      // await db.q('INSERT INTO notifications (store_id, type, message) VALUES ($1, $2, $3)', 
      //   [sub.store_id, 'BILLING_REMINDER', `결제 예정일: ${sub.next_billing_date}`]);
    }

    return { ok: true, count: subscriptions.rows.length };
  } catch (error) {
    console.error('Billing reminder error:', error);
    return { ok: false, error: error.message };
  }
}

/**
 * D+1 미납 처리
 * 구독 OVERDUE + 캠페인 PAUSED_BY_BILLING
 */
async function processOverdueBilling() {
  try {
    const yesterday = new Date();
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = yesterday.toISOString().split('T')[0];

    // D+1 미납 구독 조회 (next_billing_date가 어제이고, last_paid_at이 없거나 next_billing_date 이전)
    const overdue = await db.q(`
      SELECT s.*
      FROM store_plan_subscriptions s
      WHERE s.status = 'ACTIVE'
        AND s.next_billing_date = $1
        AND (s.last_paid_at IS NULL OR s.last_paid_at < s.next_billing_date::timestamp)
    `, [yesterdayStr]);

    for (const sub of overdue.rows) {
      // 1. 구독 상태를 OVERDUE로 변경
      await db.q(`
        UPDATE store_plan_subscriptions 
        SET status = 'OVERDUE', updated_at = now()
        WHERE id = $1
      `, [sub.id]);

      // 2. 해당 매장의 RUNNING 캠페인을 PAUSED_BY_BILLING으로 변경
      await db.q(`
        UPDATE campaigns 
        SET status = 'PAUSED_BY_BILLING', updated_at = now()
        WHERE store_id = $1 AND status = 'RUNNING'
      `, [sub.store_id]);

      console.log(`[Overdue] Store: ${sub.store_id}, Subscriptions: ${sub.id}, Campaigns paused`);
    }

    return { ok: true, count: overdue.rows.length };
  } catch (error) {
    console.error('Overdue billing error:', error);
    return { ok: false, error: error.message };
  }
}

/**
 * 결제 완료 후 자동 재개
 * 구독 ACTIVE 전환 시 PAUSED_BY_BILLING 캠페인 자동 복귀
 */
async function resumeCampaignsAfterPayment(storeId) {
  try {
    // 구독이 ACTIVE인지 확인
    const subscription = await db.q(`
      SELECT status FROM store_plan_subscriptions WHERE store_id = $1
    `, [storeId]);

    if (!subscription.rows[0] || subscription.rows[0].status !== 'ACTIVE') {
      return { ok: false, message: 'Subscription is not ACTIVE' };
    }

    // PAUSED_BY_BILLING 캠페인을 RUNNING으로 복귀
    const result = await db.q(`
      UPDATE campaigns 
      SET status = 'RUNNING', updated_at = now()
      WHERE store_id = $1 AND status = 'PAUSED_BY_BILLING'
      RETURNING id
    `, [storeId]);

    console.log(`[Resume] Store: ${storeId}, Campaigns resumed: ${result.rows.length}`);

    return { ok: true, count: result.rows.length };
  } catch (error) {
    console.error('Resume campaigns error:', error);
    return { ok: false, error: error.message };
  }
}

/**
 * 크론 작업 설정 (일 1회, 매일 새벽 2시)
 */
function startScheduler() {
  // D-2/D-1/D 알림 (매일 새벽 2시)
  cron.schedule('0 2 * * *', async () => {
    console.log('[BillingScheduler] Sending reminders...');
    await sendBillingReminders();
  });

  // D+1 미납 처리 (매일 새벽 3시)
  cron.schedule('0 3 * * *', async () => {
    console.log('[BillingScheduler] Processing overdue...');
    await processOverdueBilling();
  });

  console.log('[BillingScheduler] Started (daily at 2am, 3am)');
}

module.exports = {
  sendBillingReminders,
  processOverdueBilling,
  resumeCampaignsAfterPayment,
  startScheduler
};

