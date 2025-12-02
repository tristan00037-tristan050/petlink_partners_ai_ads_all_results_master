const { computeWithCbk }=require('./ledger_periods_cbk');
/** r12.0: CBK 반영된 순정산으로 지급 후보 미리보기 */
async function previewWithCbk(period){
  const v=await computeWithCbk(period);
  const items=(v.items||[]).filter(x=> (x.net_after_cbk||0) > 0)
    .map(x=>({ advertiser_id:x.advertiser_id, net_after_cbk:x.net_after_cbk||0 }))
    .sort((a,b)=>b.net_after_cbk-a.net_after_cbk);
  return { ok:true, period, count: items.length, items };
}
module.exports={ previewWithCbk };

