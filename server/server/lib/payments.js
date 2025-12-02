const db = require('./db');
const outbox = require('./outbox');

async function ensureOrder(order_id, store_id, amount, currency='KRW', provider='bootpay') {
  await (db.q || db.query)(
    `INSERT INTO payments(order_id, store_id, amount, currency, provider, status, created_at, updated_at)
     VALUES ($1,$2,$3,$4,$5,'PENDING', now(), now())
     ON CONFLICT (order_id) DO NOTHING`,
    [order_id, store_id, Number(amount||0), currency, provider]
  );
}

async function upsertProviderTxn(order_id, provider_txn_id) {
  if (!provider_txn_id) return;
  await (db.q || db.query)(
    `UPDATE payments
        SET provider_txn_id = COALESCE(provider_txn_id, $2)
      WHERE order_id = $1`,
    [order_id, provider_txn_id]
  );
}

async function getStatus(order_id) {
  const r = await (db.q || db.query)(
    `SELECT id, order_id, status, store_id, amount FROM payments WHERE order_id = $1`,
    [order_id]
  );
  return r && r.rows && r.rows.length > 0 ? r.rows[0] : null;
}

/** 상태 변경 + outbox 이벤트를 하나의 트랜잭션으로 기록 */
async function setStatus(order_id, status, meta = {}) {
  return db.transaction(async (client) => {
    const r = await client.query(
      `UPDATE payments
          SET status=$2,
              metadata = COALESCE(metadata,'{}')::jsonb || $3::jsonb,
              updated_at=now()
        WHERE order_id=$1
        RETURNING id, store_id, amount`,
      [order_id, status, meta]
    );
    if (!r.rows.length) return null;
    const p = r.rows[0];
    await outbox.addEventTx(client, `PAYMENT_${status}`, 'payment', p.id, {
      order_id, store_id: p.store_id, amount: p.amount, meta
    });
    return p;
  });
}

module.exports = { ensureOrder, upsertProviderTxn, setStatus, getStatus };
