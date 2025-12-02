const express=require('express'); const db=require('../lib/db'); const admin=require('../mw/admin'); const r=express.Router();

// GET /admin/ads/quality/rules  : ACTIVE/DRAFT 목록
r.get('/rules', admin.requireAdmin, async (req,res)=>{
  const q = await db.q(`SELECT channel, rule_version, status, config, effective_at, created_at
                        FROM channel_rules ORDER BY channel, rule_version DESC`);
  res.json({ ok:true, items:q.rows });
});

// PUT /admin/ads/quality/rules : {channel, rule_version?, status?, config}
r.put('/rules', admin.requireAdmin, express.json(), async (req,res)=>{
  const { channel, rule_version, status, config } = req.body||{};
  if(!channel || !config) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  const ch = String(channel).toUpperCase();
  const ver = Number(rule_version||Date.now()%100000);
  const st = (status||'DRAFT').toUpperCase();
  await db.q(`INSERT INTO channel_rules(channel, rule_version, status, config, effective_at)
              VALUES($1,$2,$3,$4::jsonb, CASE WHEN $3='ACTIVE' THEN now() ELSE NULL END)
              ON CONFLICT DO NOTHING`, [ch, ver, st, JSON.stringify(config)]);
  // ACTIVE로 올리는 경우 기존 ACTIVE는 DEPRECATED 처리
  if(st==='ACTIVE'){
    await db.q(`UPDATE channel_rules SET status='DEPRECATED' WHERE channel=$1 AND status='ACTIVE' AND rule_version<>$2`, [ch, ver]);
  }
  res.json({ ok:true, channel:ch, rule_version:ver, status:st });
});

// POST /admin/ads/quality/rules/freeze : {channel, rule_version}
r.post('/rules/freeze', admin.requireAdmin, express.json(), async (req,res)=>{
  const { channel, rule_version } = req.body||{};
  if(!channel || !rule_version) return res.status(400).json({ ok:false, code:'FIELDS_REQUIRED' });
  const ch=String(channel).toUpperCase(), ver=Number(rule_version);
  await db.q(`UPDATE channel_rules SET status='ACTIVE', effective_at=now() WHERE channel=$1 AND rule_version=$2`,[ch,ver]);
  await db.q(`UPDATE channel_rules SET status='DEPRECATED' WHERE channel=$1 AND rule_version<>$2 AND status<>'DEPRECATED'`,[ch,ver]);
  res.json({ ok:true, channel:ch, rule_version:ver, status:'ACTIVE' });
});

module.exports=r;
