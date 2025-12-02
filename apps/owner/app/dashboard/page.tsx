'use client';
import { useEffect, useState } from 'react';
import { API_BASE } from '../../lib/api';
import RequireAuth from '../../components/RequireAuth';

export default function Dashboard() {
  const [me,setMe]=useState<any>(null);
  const [stores,setStores]=useState<any[]>([]);
  const [campaigns,setCampaigns]=useState<any[]>([]);

  useEffect(()=>{
    (async()=>{
      const meRes = await fetch(API_BASE + '/bff/me', { credentials:'include' });
      const meJson = await meRes.json();
      if (!meJson?.ok) { location.href='/login'; return; }
      setMe(meJson.user);

      const s = await fetch(API_BASE + '/stores', { credentials:'include' }).then(r=>r.json());
      setStores(s.items || []);

      // 간단 요약: 첫 매장 기준 캠페인 목록
      if (s.items?.[0]) {
        const cs = await fetch(`${API_BASE}/stores/${s.items[0].id}/campaigns`, { credentials:'include' }).then(r=>r.json());
        setCampaigns(cs.items || []);
      }
    })();
  },[]);

  return (
    <RequireAuth>
      <main>
        <h2>대시보드</h2>
      {me && <p>안녕하세요, {me.email}</p>}
      <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:16}}>
        <section>
          <h3>내 매장</h3>
          <ul>{stores.map((s:any)=><li key={s.id}>{s.name} (#{s.id})</li>)}</ul>
        </section>
        <section>
          <h3>캠페인 요약(첫 매장)</h3>
          <ul>{campaigns.map((c:any)=><li key={c.id}>{c.name} — {c.status}</li>)}</ul>
        </section>
      </div>
      </main>
    </RequireAuth>
  );
}

