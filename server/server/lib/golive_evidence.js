const fs=require('fs'), os=require('os'), path=require('path'), crypto=require('crypto'), { spawnSync }=require('child_process');
const fetchFn=(global.fetch||require('undici').fetch||globalThis.fetch);
const db=require('../lib/db');
const base='http://localhost:'+ (process.env.PORT||'5902');
const H={ headers:{ 'X-Admin-Key': process.env.ADMIN_KEY||'' } };

async function pullText(p){ try{ const r=await fetchFn(base+p,H); if(!r.ok) return null; return await r.text(); }catch(_){ return null; } }
async function pullJSON(p){ try{ const r=await fetchFn(base+p,H); if(!r.ok) return null; return await r.json(); }catch(_){ return null; } }

async function buildEvidenceBundle(){
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(),'golive_'));
  const files = [];
  async function add(name, content){
    const fp=path.join(tmp,name);
    fs.writeFileSync(fp, content);
    files.push({ name, size: Buffer.byteLength(content) });
  }

  // 필수 스냅샷 수집(r10.1/r9.9/r11.4/r10.9/r11.x)
  const gate   = await pullJSON('/admin/prod/preflight') || {ok:false};
  const chkMD  = await pullText('/admin/prod/golive/checklist') || '# Runbook (n/a)';
  const sec    = await pullJSON('/admin/compliance/docs') || {ok:false};
  const ret    = await pullJSON('/admin/retention/policy/list') || {ok:false};
  const pre    = await pullJSON('/admin/prod/preflight') || {ok:false};
  const sla    = await pullJSON('/admin/reports/pilot/flip/acksla') || {ok:false};
  const ch     = await pullJSON('/admin/ledger/payouts/channels') || {ok:false};
  const ramp   = await pullJSON('/admin/reports/pilot/ramp/perf.json?days=7') || {ok:false};
  const perf14 = await pullJSON('/admin/reports/pilot/ramp/perf.json?days=14') || {ok:false};
  const batches= await pullJSON('/admin/ledger/payouts/run/batches') || {ok:false};

  await add('golive_gate.json', JSON.stringify(gate,null,2));
  await add('runbook.md', chkMD);
  await add('security_headers.json', JSON.stringify(sec,null,2));
  await add('retention_policy.json', JSON.stringify(ret,null,2));
  await add('preflight.json', JSON.stringify(pre,null,2));
  await add('acksla.json', JSON.stringify(sla,null,2));
  await add('payout_channels.json', JSON.stringify(ch,null,2));
  await add('ramp_perf7.json', JSON.stringify(ramp,null,2));
  await add('ramp_perf14.json', JSON.stringify(perf14,null,2));
  await add('payout_batches.json', JSON.stringify(batches,null,2));

  const out = path.join(os.tmpdir(), `golive_evidence_${Date.now()}.tgz`);
  const tar = spawnSync('tar',['-czf', out, '-C', tmp, '.'], { encoding:'utf8' });
  if (tar.status!==0) throw new Error('tar failed: '+tar.stderr);

  const data=fs.readFileSync(out);
  const sha=crypto.createHash('sha256').update(data).digest('hex');
  const manifest={ files, size: data.length, sha256: sha };
  const ins=await db.q(`INSERT INTO golive_evidence(name,sha256,manifest,created_by) VALUES($1,$2,$3,$4) RETURNING id`,
                       ['GoLive Evidence vFinal', sha, manifest, 'admin']);
  return { ok:true, id: ins.rows[0].id, path: out, sha256: sha, manifest };
}

module.exports={ buildEvidenceBundle };

