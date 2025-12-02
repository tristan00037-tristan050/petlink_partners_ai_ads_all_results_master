'use client';
import { useEffect, useState } from 'react';

export default function AdminCampaigns(){
  const [items,setItems] = useState<any[]>([]);
  const [err,setErr] = useState<string|undefined>();

  useEffect(()=>{(async()=>{
    try{
      // 백엔드에 /admin/reports/summary 에 캠페인 요약이 있다고 가정
      const r = await fetch('/api/admin/reports/summary');
      const j = await r.json();
      setItems(j?.campaigns ?? []); // 없으면 빈 배열
    }catch(e:any){ setErr(e.message||'불러오기 실패'); }
  })();},[]);

  return (
    <main style={{maxWidth:900}}>
      <h2>캠페인 목록(요약)</h2>
      {err && <p style={{color:'crimson'}}>{err}</p>}
      <table style={{width:'100%',borderCollapse:'collapse'}}>
        <thead><tr><th>캠페인ID</th><th>제목</th><th>매장</th><th>상태</th><th>액션</th></tr></thead>
        <tbody>
        {items.map((c:any)=>(
          <tr key={c.id}>
            <td>{c.id}</td><td>{c.title||c.name}</td><td>{c.store_name||c.store_id}</td><td>{c.status}</td>
            <td>
              <a href={`/admin/policy?cid=${encodeURIComponent(c.id)}`} style={{marginRight:8}}>정책 해제</a>
            </td>
          </tr>
        ))}
        </tbody>
      </table>
    </main>
  );
}


