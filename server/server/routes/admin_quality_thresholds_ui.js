const express=require('express'); const admin=require('../mw/admin'); const r=express.Router();
r.get('/quality/thresholds/ui', admin.requireAdmin, async (req,res)=>{
  const j=await (await fetch('http://localhost:'+ (process.env.PORT||'5902') +'/admin/reports/quality/thresholds',{ headers:{'X-Admin-Key':process.env.ADMIN_KEY||''} })).json();
  const rows=(j.items||[]).map(x=>`<tr><td>${x.channel}</td><td>${x.min_approval}</td><td>${x.max_rejection}</td></tr>`).join('');
  res.setHeader('Content-Type','text/html; charset=utf-8');
  res.end(`<!doctype html><meta charset="utf-8"><title>Quality Thresholds</title>
  <h2 style="font:14px system-ui,Arial">Quality Thresholds</h2>
  <form onsubmit="event.preventDefault();submitForm();">
    <textarea id="payload" style="width:600px;height:160px">{
  "items":[
    {"channel":"META","min_approval":0.92,"max_rejection":0.06},
    {"channel":"YOUTUBE","min_approval":0.90,"max_rejection":0.08},
    {"channel":"NAVER","min_approval":0.90,"max_rejection":0.08}
  ]}</textarea><br/>
    <button type="submit">Apply</button>
  </form>
  <h3>Current</h3>
  <table border="1" cellspacing="0" cellpadding="6"><thead><tr><th>Channel</th><th>Min Approval</th><th>Max Rejection</th></tr></thead><tbody>${rows||'<tr><td colspan=3>no data</td></tr>'}</tbody></table>
  <script>
    async function submitForm(){
      const res = await fetch('/admin/reports/quality/thresholds',{method:'POST',headers:{'Content-Type':'application/json','X-Admin-Key':'${process.env.ADMIN_KEY||''}'},body:document.getElementById('payload').value});
      if(res.ok) location.reload(); else alert('update failed');
    }
  </script>`);
});
module.exports=r;
