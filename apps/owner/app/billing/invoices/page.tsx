'use client';
import { useEffect, useState } from 'react';
import { useStoreSelection } from '../../../lib/useStoreSelection';
const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:5903';

export default function InvoicesPage(){
  const { storeId } = useStoreSelection();
  const [invoices,setInvoices]=useState<any[]>([]);

  useEffect(()=>{
    (async()=>{
      if (!storeId) return;
      const r = await fetch(`${API_BASE}/stores/${storeId}/billing/invoices`, { credentials:'include' });
      const j = await r.json().catch(()=>[]);
      setInvoices(Array.isArray(j) ? j : (j?.items||[]));
    })();
  },[storeId]);

  const badge = (s:string)=>{
    const color = s==='paid' ? '#2e7d32' : s==='overdue' ? '#c62828' : '#1565c0';
    return <span style={{background:color,color:'#fff',padding:'2px 6px',borderRadius:6,marginLeft:8}}>{s}</span>;
  };

  return (
    <main>
      <h2>인보이스</h2>
      <ul>
        {invoices.map((iv:any)=>(
          <li key={iv.id || `${iv.period_start}-${iv.period_end}`}>
            {iv.period_start} ~ {iv.period_end} — {iv.amount}{badge(iv.status)}
            {iv.status==='overdue' && <em style={{marginLeft:8,color:'#c62828'}}>미납 시 광고 자동 중단</em>}
          </li>
        ))}
      </ul>
    </main>
  );
}
