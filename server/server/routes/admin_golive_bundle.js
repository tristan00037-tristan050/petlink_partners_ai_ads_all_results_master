const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const fetchFn=(global.fetch||require('undici').fetch||globalThis.fetch);
const db=require('../lib/db');
const { checklist }=require('../lib/golive_check');
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();

const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
const H=adminCORS||((req,res,next)=>next());
const HDR={ headers:{ 'X-Admin-Key': process.env.ADMIN_KEY||'', 'Content-Type':'application/json' } };
const base='http://localhost:'+ (process.env.PORT||'5902');

r.get('/security/headers/demo', H, guard, (req,res)=>{
  res.setHeader('Content-Type','text/plain; charset=utf-8');
  res.end('security headers demo');
});

r.get('/compliance/docs', H, guard, (_req,res)=>{
  res.json({ ok:true, docs:{
    terms_version: '2025‑11',
    privacy_version: '2025‑11',
    ad_disclosure_text: '본 서비스는 광고성 정보 표기를 준수합니다.'
  }});
});

r.get('/retention/policy/list', H, guard, async (_req,res)=>{
  const q=await db.q(`SELECT table_name, ttl_days FROM pilot_retention_policy ORDER BY table_name`);
  res.json({ ok:true, items:q.rows });
});

r.post('/retention/policy/upsert', H, guard, express.json(), async (req,res)=>{
  const items = req.body?.items||[];
  for(const it of items){
    await db.q(`INSERT INTO pilot_retention_policy(table_name,ttl_days)
                VALUES($1,$2)
                ON CONFLICT(table_name) DO UPDATE SET ttl_days=EXCLUDED.ttl_days`, [it.table_name, Number(it.ttl_days||0)]);
  }
  res.json({ ok:true, upserted: items.length });
});

r.post('/prod/integration/dryrun', H, guard, express.json(), async (req,res)=>{
  const period = (req.body?.period)|| (new Date().toISOString().slice(0,7));
  // 1) 배치 빌드→승인 (r11.3)
  let bid;
  try{
    const b = await fetchFn(base+'/admin/ledger/payouts/run/build', { ...HDR, method:'POST', body: JSON.stringify({ period, commit:true, actor:'golive-dryrun' }) });
    const bj= await b.json(); bid = bj.batch_id||bj.id;
    await fetchFn(base+'/admin/ledger/payouts/run/approve', { ...HDR, method:'POST', body: JSON.stringify({ batch_id: bid, approver:'golive-approver' }) });
  }catch(e){ return res.status(500).json({ ok:false, step:'build/approve', error: e?.message }); }

  // 2) 채널 준비(MOCK 업서트) (r11.4)
  let chId;
  try{
    const ch = await fetchFn(base+'/admin/ledger/payouts/channels/upsert', { ...HDR, method:'POST', body: JSON.stringify({ name:'MOCK', kind:'MOCK', enabled:true }) });
    const cj= await ch.json(); chId = cj?.item?.id || cj?.id || 1;
  }catch(_){ chId = 1; }

  // 3) 은행파일 생성 (r11.4)
  let bfId;
  try{
    const bf = await fetchFn(base+'/admin/ledger/payouts/batch/build-bankfile', { ...HDR, method:'POST', body: JSON.stringify({ batch_id: bid, format:'CSV' }) });
    const bfj= await bf.json(); bfId = bfj?.bank_file?.id || bfj?.id || 1;
  }catch(e){ return res.status(500).json({ ok:false, step:'build-bankfile', error: e?.message }); }

  // 4) send2 (DRYRUN) (r11.4)
  try{
    const s2 = await fetchFn(base+'/admin/ledger/payouts/batch/send2', { ...HDR, method:'POST', body: JSON.stringify({ batch_id: bid, bank_file_id: bfId, channel_id: chId }) });
    const out = await s2.json();
    return res.json({ ok:true, batch_id: bid, bank_file_id: bfId, channel_id: chId, sent: !!out.ok });
  }catch(e){ return res.status(500).json({ ok:false, step:'send2', error:e?.message }); }
});

r.get('/prod/golive/checklist', H, guard, async (_req,res)=>{
  res.json(await checklist());
});

module.exports = r;

