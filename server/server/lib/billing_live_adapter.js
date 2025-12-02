const fetchFn=(global.fetch||require('node-fetch'));
async function captureLive({ advertiser_id, amount, meta={} }){
  // 실연동 전까지는 DRYRUN: 외부 호출 없이 성공 시뮬레이션
  // 운영 전환 시 여기에서 PG/부트페이 라이브 API 호출 연결
  if(!process.env.BOOTPAY_LIVE_KEY){
    return { ok:false, code:'NO_LIVE_KEY', message:'Missing live key (still in DRYRUN by default)' };
  }
  // 샘플: 성공 시뮬
  return { ok:true, txid:'LIVE_SIM_'+Math.random().toString(36).slice(2), meta };
}
module.exports={ captureLive };

