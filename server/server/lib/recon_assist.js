const db=require('../lib/db');

/** diff_id 기준 자동 매칭 후보 제안
 *  - txid 일치 우선
 *  - 금액/기간(±7일) 근접
 *  - 간단 점수: txid매치 +50, 금액매치 +30, 날짜가까움 +0~20
 */
async function suggestForDiff(diff_id){
  const d=(await db.q(`SELECT * FROM recon_diffs WHERE id=$1`,[diff_id])).rows[0];
  if(!d) return { ok:false, code:'DIFF_NOT_FOUND' };
  const cand=(await db.q(`
    WITH L AS (
      SELECT 'live_ledger' AS src, COALESCE(txid, '') AS txid, amount, advertiser_id, event_at AS created_at FROM live_ledger WHERE event_at >= now()-interval '7 days'
      UNION ALL
      SELECT 'ad_payments' AS src, COALESCE(invoice_no, '') AS txid, amount, advertiser_id, created_at FROM ad_payments WHERE created_at >= now()-interval '7 days'
      UNION ALL
      SELECT 'live_billing_journal' AS src, COALESCE(id::text, '') AS txid, amount, advertiser_id, created_at FROM live_billing_journal WHERE created_at >= now()-interval '7 days'
    )
    SELECT * FROM L
    WHERE ($1::text IS NULL OR $1='' OR txid=$1) OR (amount=$2)
    ORDER BY created_at DESC
    LIMIT 200
  `,[d.txid||null, d.amount||null])).rows;

  const score = (x)=>{
    let s=0;
    if(d.txid && x.txid===d.txid) s+=50;
    if(d.amount!=null && x.amount===d.amount) s+=30;
    if(d.created_at && x.created_at){
      const ms=Math.abs(new Date(d.created_at).getTime()-new Date(x.created_at).getTime());
      s+= Math.max(0, 20 - Math.min(20, Math.floor(ms/ (24*3600*1000)))); // 일차이 작을수록 가산
    }
    return s;
  };
  const items = cand.map(c=>({ ...c, score: score(c) }))
                    .sort((a,b)=>b.score-a.score)
                    .slice(0,10);
  return { ok:true, diff: { id: d.id, txid: d.txid, amount: d.amount }, suggestions: items };
}
module.exports={ suggestForDiff };

