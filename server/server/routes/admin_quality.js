const express = require('express');
const db = require('../lib/db');
const admin = require('../mw/admin');

const r = express.Router();

/** GET /admin/reports/quality.json?days=7 */
r.get('/quality.json', admin.requireAdmin, async (req,res)=>{
  const days = Math.max(1, Math.min(90, parseInt(req.query.days||'7',10)));
  const params = [days];

  const chq = await db.q(`
    WITH base AS (
      SELECT channel,
             COALESCE((flags->>'forbidden_count')::int,0) AS forb,
             CASE WHEN format_ok THEN 1 ELSE 0 END AS fmt
      FROM ad_creatives
      WHERE created_at >= now() - ($1||' days')::interval
    )
    SELECT channel,
           count(*) AS total,
           COALESCE(ROUND(AVG(fmt)::numeric, 4), 0) AS format_rate,
           COALESCE(SUM(forb), 0) AS forb_sum
    FROM base
    GROUP BY channel
    ORDER BY channel NULLS LAST
  `, params);

  const rej = await db.q(`
    WITH src AS (
      SELECT jsonb_array_elements_text(COALESCE(flags->'reject_reasons', '[]'::jsonb)) AS reason
      FROM ad_creatives
      WHERE created_at >= now() - ($1||' days')::interval
    )
    SELECT reason, count(*) AS cnt
    FROM src
    GROUP BY reason
    ORDER BY cnt DESC NULLS LAST
    LIMIT 10
  `, params);

  res.json({ ok:true, days, channels: chq.rows, top_reject_reasons: rej.rows });
});

/** GET /admin/reports/quality (HTML) */
r.get('/quality', admin.requireAdmin, async (req,res)=>{
  const chq = await db.q(`
    WITH base AS (
      SELECT channel,
             COALESCE((flags->>'forbidden_count')::int,0) AS forb,
             CASE WHEN format_ok THEN 1 ELSE 0 END AS fmt
      FROM ad_creatives
      WHERE created_at >= now() - interval '7 days'
    )
    SELECT channel, count(*) AS total,
           COALESCE(ROUND(AVG(fmt)::numeric, 4), 0) AS format_rate,
           COALESCE(SUM(forb), 0) AS forb_sum
    FROM base
    GROUP BY channel
    ORDER BY channel NULLS LAST
  `);
  const rej = await db.q(`
    WITH src AS (
      SELECT jsonb_array_elements_text(COALESCE(flags->'reject_reasons','[]'::jsonb)) AS reason
      FROM ad_creatives
      WHERE created_at >= now() - interval '7 days'
    )
    SELECT reason, count(*) AS cnt FROM src
    GROUP BY reason ORDER BY cnt DESC NULLS LAST LIMIT 10
  `);

  const H=(l,v)=>`<div style="border:1px solid #ddd;border-radius:6px;padding:12px;margin:8px;display:inline-block;min-width:220px">
    <div style="font-size:12px;color:#666">${l}</div><div style="font-size:22px;font-weight:700">${v}</div></div>`;
  const pct=(x)=> (Math.round((Number(x||0)*10000))/100)+'%';
  const rows = chq.rows.map(r =>
    `<tr><td>${r.channel||'-'}</td><td>${r.total}</td><td>${pct(r.format_rate)}</td><td>${r.forb_sum}</td></tr>`
  ).join('');
  const rejRows = rej.rows.map(r=>`<tr><td>${r.reason||'-'}</td><td>${r.cnt}</td></tr>`).join('');

  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>AI Quality Report</title>
  <div style="font:14px system-ui,Arial;padding:16px">
    <h2>AI 품질 리포트(최근 7일)</h2>
    <h3>채널별 지표</h3>
    <table border="1" cellspacing="0" cellpadding="6">
      <thead><tr><th>채널</th><th>총 건수</th><th>포맷 적합률</th><th>금칙어 합계</th></tr></thead>
      <tbody>${rows || '<tr><td colspan="4">데이터 없음</td></tr>'}</tbody>
    </table>
    <h3>리젝 Top-10</h3>
    <table border="1" cellspacing="0" cellpadding="6">
      <thead><tr><th>사유</th><th>건수</th></tr></thead>
      <tbody>${rejRows || '<tr><td colspan="2">데이터 없음</td></tr>'}</tbody>
    </table>
  </div>`);
});

module.exports = r;
