module.exports = {
  async registerMethod(){ return { ok:true, token:'tok_bootpay_placeholder' }; },
  async authorize(){ return { ok:true, provider_txn_id:'auth_bootpay_placeholder' }; },
  async capture(){ return { ok:true, provider_txn_id:'cap_bootpay_placeholder' }; },
  async verify(){ return { ok:true, status:'CAPTURED' }; },
  verifyWebhook(rawBuf, req){
    const crypto=require('crypto');
    const secret=process.env.PAYMENT_WEBHOOK_SECRET||''; const ts=req.get('X-Webhook-Timestamp'); const sig=req.get('X-Webhook-Signature');
    if(!secret||!ts||!sig) return { ok:false, code:'SECRET_OR_HEADERS_EMPTY' };
    const now=Math.floor(Date.now()/1000); const t=parseInt(ts||'0',10);
    if(!t || Math.abs(now-t) > 300) return { ok:false, code:'TS_WINDOW_EXCEEDED' };
    const mac=crypto.createHmac('sha256',secret).update(String(t)).update('.').update(rawBuf).digest('hex');
    try{ const ok=crypto.timingSafeEqual(Buffer.from(mac,'hex'),Buffer.from(sig,'hex')); return ok?{ok:true}:{ok:false,code:'SIG_MISMATCH'}; }
    catch{ return { ok:false, code:'SIG_VERIFY_ERROR' }; }
  }
};
