const db = require('./db'); const outbox = require('./outbox');
async function ensureInvoice(invoice_no, advertiser_id, amount, currency='KRW'){ await db.q(
 `INSERT INTO ad_invoices(invoice_no,advertiser_id,amount,currency,status,created_at,updated_at)
  VALUES($1,$2,$3,$4,'DUE',now(),now()) ON CONFLICT(invoice_no) DO NOTHING`,
 [invoice_no, advertiser_id, Number(amount||0), currency]); }
async function ensurePayment(invoice_no, advertiser_id, amount, currency='KRW', provider='bootpay'){ await db.q(
 `INSERT INTO ad_payments(invoice_no,advertiser_id,amount,currency,provider,status,created_at,updated_at)
  VALUES($1,$2,$3,$4,$5,'PENDING',now(),now()) ON CONFLICT DO NOTHING`,
 [invoice_no, advertiser_id, Number(amount||0), currency, provider]); }
async function bindMethod(invoice_no, method_id){ await db.q(`UPDATE ad_payments SET method_id=$2 WHERE invoice_no=$1`,[invoice_no,method_id]); }
async function upsertProviderTxn(invoice_no, provider_txn_id){ if(!provider_txn_id) return; await db.q(
 `UPDATE ad_payments SET provider_txn_id=COALESCE(provider_txn_id,$2) WHERE invoice_no=$1`, [invoice_no, provider_txn_id]); }
async function setStatus(invoice_no, status, meta={}){ return db.transaction(async(c)=>{ const pr=await c.query(
 `UPDATE ad_payments SET status=$2, metadata=COALESCE(metadata,'{}')::jsonb || $3::jsonb, updated_at=now()
  WHERE invoice_no=$1 RETURNING id, advertiser_id, amount`, [invoice_no, status, meta]); if(!pr.rows.length) return null;
 const p=pr.rows[0]; if(status==='CAPTURED') await c.query(`UPDATE ad_invoices SET status='PAID', updated_at=now() WHERE invoice_no=$1`,[invoice_no]);
 if(status==='CANCELED') await c.query(`UPDATE ad_invoices SET status='CANCELED', updated_at=now() WHERE invoice_no=$1`,[invoice_no]);
 await outbox.addEventTx(c, `AD_BILLING_${status}`, 'ad_payment', p.id, { invoice_no, advertiser_id:p.advertiser_id, amount:p.amount, meta });
 return p; });}
async function addPaymentMethod({advertiser_id,pm_type,provider,token,brand=null,last4=null,set_default=false}){ return db.transaction(async(c)=>{ await c.query(
 `INSERT INTO payment_methods(advertiser_id,pm_type,provider,token,brand,last4,is_default)
  VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(advertiser_id,provider,token) DO NOTHING`,
 [advertiser_id,pm_type,provider,token,brand,last4,!!set_default]); if(set_default){ await c.query(
 `UPDATE payment_methods SET is_default=(id=(SELECT id FROM payment_methods WHERE advertiser_id=$1 AND provider=$2 AND token=$3 LIMIT 1))
  WHERE advertiser_id=$1`, [advertiser_id, provider, token]); } });}
async function setDefaultMethod(advertiser_id,id){ return db.transaction(async(c)=>{ await c.query(`UPDATE payment_methods SET is_default=false WHERE advertiser_id=$1`,[advertiser_id]);
 await c.query(`UPDATE payment_methods SET is_default=true WHERE advertiser_id=$1 AND id=$2`,[advertiser_id,id]); });}
async function deleteMethod(advertiser_id,id){ await db.q(`DELETE FROM payment_methods WHERE advertiser_id=$1 AND id=$2`,[advertiser_id,id]); }
async function listMethods(advertiser_id){ const {rows}=await db.q(`SELECT id,pm_type,provider,brand,last4,is_default,created_at FROM payment_methods WHERE advertiser_id=$1 ORDER BY id DESC`,[advertiser_id]); return rows; }
// 결제수단 설정(인보이스 기준)
async function setMethod(invoice_no, method_id){
  if(!method_id) return; // 샌드박스: 없음 허용
  await db.q(`UPDATE ad_payments SET method_id=$2 WHERE invoice_no=$1`, [invoice_no, method_id]);
}
module.exports={ ensureInvoice, ensurePayment, bindMethod, upsertProviderTxn, setStatus, addPaymentMethod, setDefaultMethod, deleteMethod, listMethods, setMethod };
