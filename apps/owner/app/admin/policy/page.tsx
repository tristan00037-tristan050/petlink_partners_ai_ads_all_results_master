'use client';
import { useState, useEffect } from 'react';
import { useSearchParams } from 'next/navigation';

export default function AdminPolicy() {
  const searchParams = useSearchParams();
  const [cid,setCid]=useState('');
  const [actor,setActor]=useState('admin@example.com');
  const [note,setNote]=useState('');
  const [msg,setMsg]=useState<string|undefined>(undefined);

  useEffect(()=>{
    const cidParam = searchParams.get('cid');
    if (cidParam) setCid(cidParam);
  },[searchParams]);

  const resolve = async ()=>{
    setMsg(undefined);
    const r = await fetch(`/api/admin/policy/campaigns/${cid}/resolve`, {
      method:'POST',
      headers:{ 'Content-Type':'application/json', 'X-Admin-Actor': actor },
      body: JSON.stringify({ resolved_by: actor, resolved_note: note })
    });
    const j = await r.json().catch(()=>({}));
    setMsg((r.ok && j?.ok!==false) ? '정책 해제 완료' : (j?.message || j?.code || `실패(${r.status})`));
  };

  return (
    <main style={{maxWidth:640}}>
      <h2>정책 해제 (Admin)</h2>
      <input placeholder="캠페인 ID" value={cid} onChange={e=>setCid(e.target.value)} />
      <input placeholder="해제자" value={actor} onChange={e=>setActor(e.target.value)} />
      <input placeholder="사유" value={note} onChange={e=>setNote(e.target.value)} />
      <button onClick={resolve} disabled={!cid}>해제 실행</button>
      {msg && <p style={{marginTop:8}}>{msg}</p>}
    </main>
  );
}
