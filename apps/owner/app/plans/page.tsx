'use client';
import { useEffect, useState } from 'react';
import { useStoreSelection } from '../../lib/useStoreSelection';
import { useToast } from '../../components/Toast';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:5903';

export default function PlansPage(){
  const [plans,setPlans] = useState<any[]>([]);
  const [loading,setLoading]=useState(true);
  const [err,setErr]=useState<string|undefined>();
  const { storeId } = useStoreSelection();
  const toast = useToast();

  useEffect(()=>{
    (async()=>{
      try{
        const r = await fetch(`${API_BASE}/plans`, { credentials:'include' });
        const j = await r.json();
        setPlans(Array.isArray(j?.plans) ? j.plans : j);
      }catch(e:any){ setErr(e.message||'불러오기 실패'); }
      setLoading(false);
    })();
  },[]);

  const subscribe = async (planId:string)=>{
    if (!storeId) { toast.error('먼저 매장을 생성/선택해 주세요.'); return; }
    const r = await fetch(`${API_BASE}/stores/${storeId}/subscribe`, {
      method:'POST', credentials:'include',
      headers:{ 'Content-Type':'application/json' },
      body: JSON.stringify({ plan_id: planId })
    });
    const j = await r.json().catch(()=>({}));
    if (!r.ok || j?.ok===false) { toast.error(j?.message||j?.code||`실패(${r.status})`); return; }
    toast.success('구독이 변경되었습니다.');
  };

  if (loading) return <main>로딩...</main>;
  if (err) return <main style={{color:'crimson'}}>{err}</main>;

  return (
    <main>
      <h2>요금제</h2>
      <ul>
        {plans.map((p:any)=>(
          <li key={p.id} style={{margin:'8px 0'}}>
            <b>{p.name}</b> — {p.price}/월
            <button
              data-testid={`plan-select-${p.id}`}
              onClick={()=>subscribe(p.id)}
              style={{marginLeft:8}}
            >
              이 플랜으로
            </button>
          </li>
        ))}
      </ul>
    </main>
  );
}
