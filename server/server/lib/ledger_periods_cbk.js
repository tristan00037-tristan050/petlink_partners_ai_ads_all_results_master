const db=require('../lib/db');

/** r12.0: 마감 스냅샷 + CBK 영향 합성(존재 시 스냅샷 우선, 없으면 빈 집합) */
async function computeWithCbk(period){
  const base=(await db.q(`
    SELECT advertiser_id, charges, refunds, net, entries
    FROM ledger_period_snapshots WHERE period=$1
    ORDER BY advertiser_id`, [period])).rows;

  const cbk=(await db.q(`
    SELECT c.advertiser_id,
      SUM(CASE WHEN c.outcome='WIN'       THEN a.amount ELSE 0 END)::int  AS cbk_win_amount,
      SUM(CASE WHEN c.outcome='LOSE'      THEN a.amount ELSE 0 END)::int  AS cbk_lose_amount,
      SUM(CASE WHEN c.outcome='WRITE_OFF' THEN a.amount ELSE 0 END)::int  AS cbk_write_off_amount
    FROM cbk_adjustments a
    JOIN chargeback_cases c ON c.id=a.case_id
    WHERE date_trunc('month', c.closed_at) = date_trunc('month', to_timestamp($1,'YYYY-MM'))
    GROUP BY c.advertiser_id`, [period+'-01'])).rows;

  const byAdv=new Map();
  for(const r of base){ byAdv.set(r.advertiser_id, { ...r, cbk_win_amount:0, cbk_lose_amount:0, cbk_write_off_amount:0 }); }
  for(const c of cbk){
    const t=byAdv.get(c.advertiser_id)||{ advertiser_id:c.advertiser_id, charges:0, refunds:0, net:0, entries:0, cbk_win_amount:0, cbk_lose_amount:0, cbk_write_off_amount:0 };
    t.cbk_win_amount       = (t.cbk_win_amount||0)       + (c.cbk_win_amount||0);
    t.cbk_lose_amount      = (t.cbk_lose_amount||0)      + (c.cbk_lose_amount||0);
    t.cbk_write_off_amount = (t.cbk_write_off_amount||0) + (c.cbk_write_off_amount||0);
    byAdv.set(c.advertiser_id, t);
  }
  const items=[...byAdv.values()].map(x=>{
    const cbkImpact = (x.cbk_lose_amount||0) + (x.cbk_write_off_amount||0); // LOSE/WRITE_OFF는 순정산에서 차감
    return { ...x, cbk_net_impact: cbkImpact, net_after_cbk: (x.net||0) - cbkImpact };
  });
  const sum=(a,b)=>a+(+b||0);
  const agg=items.reduce((m,r)=>({
    charges: sum(m.charges,r.charges), refunds: sum(m.refunds,r.refunds), net: sum(m.net,r.net),
    cbk_win_amount: sum(m.cbk_win_amount,r.cbk_win_amount),
    cbk_lose_amount: sum(m.cbk_lose_amount,r.cbk_lose_amount),
    cbk_write_off_amount: sum(m.cbk_write_off_amount,r.cbk_write_off_amount),
    cbk_net_impact: sum(m.cbk_net_impact,r.cbk_net_impact),
    net_after_cbk: sum(m.net_after_cbk,r.net_after_cbk),
    entries: sum(m.entries,r.entries)
  }), { charges:0, refunds:0, net:0, cbk_win_amount:0, cbk_lose_amount:0, cbk_write_off_amount:0, cbk_net_impact:0, net_after_cbk:0, entries:0 });

  return { ok:true, period, count: items.length, total: agg, items };
}

/** r12.0: 스냅샷 행에 CBK 컬럼 반영(스냅샷이 이미 존재하는 경우에만 UPDATE; 없으면 스킵) */
async function applyCbkToSnapshot(period){
  const v=await computeWithCbk(period);
  let updated=0;
  for(const r of v.items){
    const q=await db.q(`
      UPDATE ledger_period_snapshots
         SET cbk_win_amount=$3, cbk_lose_amount=$4, cbk_write_off_amount=$5,
             cbk_net_impact=$6,
             extras = COALESCE(extras,'{}'::jsonb) || jsonb_build_object('net_after_cbk',$7::integer)
       WHERE period=$1 AND advertiser_id=$2`,
      [period, r.advertiser_id, r.cbk_win_amount||0, r.cbk_lose_amount||0, r.cbk_write_off_amount||0, r.cbk_net_impact||0, r.net_after_cbk||0]);
    updated += q.rowCount||0;
  }
  return { ok:true, period, updated, count:v.count };
}

function toCsv(rows){
  const header = 'advertiser_id,charges,refunds,net,cbk_win_amount,cbk_lose_amount,cbk_write_off_amount,cbk_net_impact,net_after_cbk,entries';
  const lines = rows.map(r=>[
    r.advertiser_id, r.charges||0, r.refunds||0, r.net||0,
    r.cbk_win_amount||0, r.cbk_lose_amount||0, r.cbk_write_off_amount||0,
    r.cbk_net_impact||0, r.net_after_cbk||0, r.entries||0
  ].join(','));
  return [header, ...lines].join('\n');
}

function toMarkdown(v){
  const t=v.total||{};
  const lines=[
    `# Period + CBK Report`,
    `- period: ${v.period}`,
    `- advertisers: ${v.count||0}`,
    `- charges: ${t.charges||0}`,
    `- refunds: ${t.refunds||0}`,
    `- net(before CBK): ${t.net||0}`,
    `- CBK lose: ${t.cbk_lose_amount||0}  write_off: ${t.cbk_write_off_amount||0}  win: ${t.cbk_win_amount||0}`,
    `- net_after_cbk: ${t.net_after_cbk||0}`,
    ``,
    `## Top (by net_after_cbk)`,
    `advertiser_id,net_after_cbk,cbk_impact`,
    ...((v.items||[]).sort((a,b)=> (b.net_after_cbk||0) - (a.net_after_cbk||0)).slice(0,20)
       .map(r=>`${r.advertiser_id},${r.net_after_cbk||0},${r.cbk_net_impact||0}`))
  ];
  return lines.join('\n');
}

module.exports={ computeWithCbk, applyCbkToSnapshot, toCsv, toMarkdown };

