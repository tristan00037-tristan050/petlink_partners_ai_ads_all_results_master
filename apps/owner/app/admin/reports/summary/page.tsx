'use client';
import { useEffect, useState } from 'react';

export default function AdminReportSummary() {
  const [data,setData]=useState<any>(null);
  const [err,setErr]=useState<string|undefined>();
  useEffect(()=>{
    (async()=>{
      try{
        const r = await fetch('/api/admin/reports/summary');
        const j = await r.json();
        setData(j);
      }catch(e:any){ setErr(e.message||'불러오기 실패'); }
    })();
  },[]);
  return (
    <main>
      <h2>요약 리포트</h2>
      {err && <p style={{color:'crimson'}}>{err}</p>}
      <pre style={{background:'#f7f7f7',padding:12}}>{JSON.stringify(data,null,2)}</pre>
    </main>
  );
}
