'use client';
import { useState } from 'react';

export default function AdminExport() {
  const [includeEnv, setIncludeEnv] = useState(false);
  const dl = (target:'server'|'client'|'admin'|'all')=>{
    const q = new URLSearchParams();
    q.set('target', target);
    if (includeEnv) q.set('includeEnv','1');
    window.open(`/api/export/zip?${q.toString()}`, '_blank');
  };
  return (
    <main style={{maxWidth:600}}>
      <h2>프로젝트 ZIP 내보내기</h2>
      <label style={{display:'block',margin:'8px 0'}}>
        <input type="checkbox" checked={includeEnv} onChange={e=>setIncludeEnv(e.target.checked)} />
        &nbsp;.env 포함(주의)
      </label>
      <div style={{display:'flex',gap:8,flexWrap:'wrap'}}>
        <button onClick={()=>dl('server')}>서버 ZIP</button>
        <button onClick={()=>dl('client')}>클라이언트 ZIP</button>
        <button onClick={()=>dl('admin')}>어드민 ZIP</button>
        <button onClick={()=>dl('all')}>전체 ZIP</button>
      </div>
    </main>
  );
}
