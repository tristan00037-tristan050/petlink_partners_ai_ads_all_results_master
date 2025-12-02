const db = require('../lib/db');

function periodBaseTs(period){ // 'YYYY-MM' -> 'YYYY-MM-01 00:00:00'
  return period + '-01';
}

async function computePeriod(period){
  const base = periodBaseTs(period);
  const q = await db.q(`
    WITH base AS (
      SELECT advertiser_id,
             SUM(CASE WHEN amount>0 THEN amount ELSE 0 END)::int AS charges,
             SUM(CASE WHEN amount<0 THEN -amount ELSE 0 END)::int AS refunds,
             SUM(amount)::int AS net,
             COUNT(*)::int AS entries
      FROM live_ledger
      WHERE date_trunc('month', event_at) = date_trunc('month', $1::date)
      GROUP BY advertiser_id
    )
    SELECT * FROM base ORDER BY advertiser_id
  `,[base]);

  const totals = q.rows.reduce((acc,r)=>{
    acc.charges = (acc.charges||0) + (r.charges||0);
    acc.refunds = (acc.refunds||0) + (r.refunds||0);
    acc.net     = (acc.net||0)     + (r.net||0);
    acc.entries = (acc.entries||0) + (r.entries||0);
    return acc;
  },{charges:0,refunds:0,net:0,entries:0});

  return { ok:true, period, items:q.rows, totals };
}

async function closePeriod(period, actor, dryrun=true){
  const comp = await computePeriod(period);
  if(!dryrun){
    await db.q(`INSERT INTO ledger_periods(period,status,totals,closed_by,closed_at)
                VALUES($1,'CLOSED',$2,$3,now())
                ON CONFLICT(period) DO UPDATE SET status='CLOSED', totals=EXCLUDED.totals, closed_by=EXCLUDED.closed_by, closed_at=EXCLUDED.closed_at`,
                [period, comp.totals, actor||'admin']);
    // 스냅샷 재생성(간단히 삭제 후 삽입)
    await db.q(`DELETE FROM ledger_period_snapshots WHERE period=$1`,[period]);
    for(const r of comp.items){
      await db.q(`INSERT INTO ledger_period_snapshots(period,advertiser_id,charges,refunds,net,entries)
                  VALUES($1,$2,$3,$4,$5,$6)`,
                  [period, r.advertiser_id, r.charges, r.refunds, r.net, r.entries]);
    }
  }
  return { ok:true, dryrun, ...comp };
}

async function getStatus(){
  const q = await db.q(`SELECT period,status,closed_by,closed_at FROM ledger_periods ORDER BY period DESC LIMIT 24`);
  return { ok:true, items:q.rows };
}

module.exports = { computePeriod, closePeriod, getStatus };

