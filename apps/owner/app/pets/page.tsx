'use client';
import { useEffect, useState } from 'react';
import { useStoreSelection } from '../../lib/useStoreSelection';
import { useToast } from '../../components/Toast';
const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:5903';

export default function PetsPage(){
  const { storeId } = useStoreSelection();
  const [list,setList] = useState<any[]>([]);
  const [name,setName] = useState('');
  const toast = useToast();

  const load = async ()=>{
    if (!storeId) return;
    const r = await fetch(`${API_BASE}/stores/${storeId}/pets`, { credentials:'include' });
    const j = await r.json().catch(()=>[]);
    setList(Array.isArray(j) ? j : (j?.items||[]));
  };

  useEffect(()=>{ load(); },[storeId]);

  const add = async ()=>{
    if (!storeId) { toast.error('먼저 매장을 선택하세요.'); return; }
    const r = await fetch(`${API_BASE}/stores/${storeId}/pets`, {
      method:'POST', credentials:'include',
      headers:{ 'Content-Type':'application/json' },
      body: JSON.stringify({ name })
    });
    if (!r.ok) { toast.error(`등록 실패(${r.status})`); return; }
    setName('');
    toast.success('등록되었습니다.');
    load();
  };

  return (
    <main>
      <h2>반려동물</h2>
      <div>
        <input data-testid="pet-name" placeholder="이름" value={name} onChange={e=>setName(e.target.value)} />
        <button data-testid="pet-add" onClick={add}>등록</button>
      </div>
      <ul>
        {list.map((p:any)=> <li key={p.id||p.name}>{p.name}</li>)}
      </ul>
    </main>
  );
}
