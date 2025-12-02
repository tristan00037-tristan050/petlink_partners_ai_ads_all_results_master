'use client';
import { useState } from 'react';

export default function AdminOps() {
  const [msg,setMsg]=useState<string|undefined>();
  const run = async ()=>{
    setMsg(undefined);
    const r = await fetch('/api/admin/ops/scheduler/run', { method:'POST' });
    const j = await r.json().catch(()=>({}));
    setMsg((r.ok && j?.ok!==false) ? '스케줄러 트리거 완료' : (j?.message || j?.code || `실패(${r.status})`));
  };
  return (
    <main style={{maxWidth:640}}>
      <h2>운영 스케줄러 트리거</h2>
      <button onClick={run}>Run billing_scheduler</button>
      {msg && <p style={{marginTop:8}}>{msg}</p>}
    </main>
  );
}
