const express=require('express'); let admin; try{ admin=require('../mw/admin_gate'); }catch(_){ admin=require('../mw/admin'); }
const { adminCORS }=(function(){ try{ return require('../mw/cors_split'); }catch(_){ return {}; } })();
const fetchFn=(global.fetch||require('undici').fetch||globalThis.fetch);
const db=require('../lib/db');
const { buildEvidenceBundle }=require('../lib/golive_evidence');
let alertsCh=null; try{ alertsCh=require('../lib/alerts_channels'); }catch(_){ alertsCh=null; }

const r=express.Router(); const guard=(admin?.requireAdminAny||admin?.requireAdmin);
const base='http://localhost:'+ (process.env.PORT||'5902');
const H={ headers:{ 'X-Admin-Key': process.env.ADMIN_KEY||'', 'Content-Type':'application/json' } };

async function pull(p){ try{ const rs=await fetchFn(base+p,{ headers:{ 'X-Admin-Key': process.env.ADMIN_KEY||'' }}); if(!rs.ok) return null; return await rs.json(); }catch(_){ return null; } }

r.get('/prod/tday/status', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  const gate = await pull('/admin/prod/golive/checklist') || {ok:false};
  const launch= await pull('/admin/prod/live/subs/policy?advertiser_id=0') || {ok:false};
  const policy= await pull('/admin/prod/live/subs/policy?advertiser_id=0') || {ok:false};
  res.json({ ok:true, gate, launch, policy });
});

r.post('/prod/tday/prepare', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const dry = req.body?.dryrun!==false; // default true
  // 사전 체크리스트 스냅샷(런북 MD 확보)
  const rb = await fetchFn(base+'/admin/prod/golive/checklist',{ headers:{ 'X-Admin-Key': process.env.ADMIN_KEY||'' }});
  const md = rb.ok? await rb.text().catch(()=>'# Runbook (n/a)') : '# Runbook (n/a)';
  const mdText = typeof md === 'string' ? md : '# Runbook (n/a)';
  await db.q(`INSERT INTO golive_audit(kind,actor,payload,ok) VALUES('prep',$1,$2,TRUE)`, [req.admin?.sub||'admin', { dryrun: dry, note:'tday prepare', md: mdText }]);
  if(alertsCh) try{ await alertsCh.notifyWithSeverity('info','TDAY_PREP',{ dryrun: dry, at: new Date().toISOString() }); }catch(_){}
  res.json({ ok:true, dryrun: dry });
});

r.post('/prod/tday/launch', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { initial_percent=5, advertiser_id=0, dryrun=true } = req.body||{};
  let passed=true, details={};
  // Gate 확인
  const gate = await pull('/admin/prod/golive/checklist'); details.gate=gate; passed=passed && !!(gate?.ok);
  // 전역 커밋(건조 실행 시 skip)
  if(!dryrun){
    try{
      const rs=await fetchFn(base+'/admin/prod/launch/commit?committed=true',{ method:'POST', headers:{ 'X-Admin-Key': process.env.ADMIN_KEY||'' }});
      details.launch_commit=rs.ok;
    }catch(e){ details.launch_commit=false; }
  }else{ details.launch_commit='dryrun'; }
  // 초기 퍼센트 적용(글로벌 정책 0번)
  const body=JSON.stringify({ advertiser_id, enabled:true, percent_live: initial_percent });
  try{
    const p=await fetchFn(base+'/admin/prod/live/subs/policy',{ method:'POST', ...H, body });
    details.policy_set = p.ok;
  }catch(e){ details.policy_set=false; }
  await db.q(`INSERT INTO golive_audit(kind,actor,payload,ok) VALUES('launch',$1,$2,TRUE)`, [req.admin?.sub||'admin', { dryrun, initial_percent, advertiser_id }]);
  if(alertsCh) try{ await alertsCh.notifyWithSeverity('info','TDAY_LAUNCH',{ dryrun, initial_percent: initial_percent, advertiser_id, at: new Date().toISOString() }); }catch(_){}
  res.json({ ok:true, dryrun, details });
});

r.post('/prod/tday/rollback', adminCORS||((req,res,n)=>n()), guard, express.json(), async (req,res)=>{
  const { advertiser_id=0, reason='guard_fail', dryrun=true } = req.body||{};
  let result='dryrun';
  if(!dryrun){
    // r10.7 수동 롤백 엔드포인트 사용(존재하지 않아도 무해)
    try{
      const rs=await fetchFn(base+'/admin/prod/live/subs/ramp/rollback',{ method:'POST', headers:{ 'X-Admin-Key': process.env.ADMIN_KEY||'' }});
      result = rs.ok ? 'rolled_back' : 'rollback_failed';
    }catch(_){ result='rollback_failed'; }
  }
  await db.q(`INSERT INTO golive_audit(kind,actor,payload,ok) VALUES('rollback',$1,$2,TRUE)`, [req.admin?.sub||'admin', { advertiser_id, reason, dryrun }]);
  if(alertsCh) try{ await alertsCh.notifyWithSeverity('critical','TDAY_ROLLBACK',{ advertiser_id, reason, dryrun, at: new Date().toISOString() }); }catch(_){}
  res.json({ ok:true, dryrun, result });
});

r.get('/prod/golive/evidence/build', adminCORS||((req,res,n)=>n()), guard, async (_req,res)=>{
  try{
    const out = await buildEvidenceBundle();
    // 감사 로그
    await db.q(`INSERT INTO golive_audit(kind,actor,payload,ok) VALUES('evidence',$1,$2,TRUE)`, ['admin', { id: out.id, sha256: out.sha256 }]);
    // 파일 스트림 반환
    res.setHeader('Content-Type','application/gzip');
    res.setHeader('Content-Disposition','attachment; filename="golive_evidence.tgz"');
    res.end(require('fs').readFileSync(out.path));
  }catch(e){
    res.status(500).json({ ok:false, error: String(e?.message||e) });
  }
});

module.exports=r;

