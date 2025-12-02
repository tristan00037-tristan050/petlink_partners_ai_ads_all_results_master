const crypto=require('crypto');
module.exports={ async validateToken(pm){return{ok:true,sandbox:true,pm}},
async authorize(){return{ok:true,status:'AUTHORIZED',sandbox:true}},
async capture(){return{ok:true,status:'CAPTURED',sandbox:true,provider_txn_id:'sbx-'+Date.now()}},
async verify(){return{ok:true,status:'CAPTURED',sandbox:true}},
async webhookVerify({raw,ts,sig,secret}){const mac=crypto.createHmac('sha256',String(secret||'')).update(String(ts)).update('.').update(raw).digest('hex');
try{const ok=sig&&crypto.timingSafeEqual(Buffer.from(mac,'utf8'),Buffer.from(sig,'utf8'));return{ok:!!ok,sandbox:true}}catch{return{ok:false,sandbox:true}}} };
