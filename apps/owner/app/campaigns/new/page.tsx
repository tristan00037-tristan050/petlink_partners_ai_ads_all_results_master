'use client';
import { useEffect, useState } from 'react';
import { useStoreSelection } from '../../lib/useStoreSelection';
import { useToast } from '../../components/Toast';
const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:5903';

export default function NewCampaign(){
  const { storeId } = useStoreSelection();
  const [title,setTitle] = useState('');
  const [text,setText] = useState('');
  const [blocked,setBlocked] = useState<string|undefined>();
  const toast = useToast();

  useEffect(()=>{
    // 구독/빌링 가드: 필요 시 서버에서 /stores/:id 상태를 조회하여 표시
  },[storeId]);

  const create = async ()=>{
    setBlocked(undefined);
    if (!storeId) { toast.error('먼저 매장을 선택하세요.'); return; }
    const r = await fetch(`${API_BASE}/stores/${storeId}/campaigns`, {
      method:'POST', credentials:'include',
      headers:{ 'Content-Type':'application/json' },
      body: JSON.stringify({ title, primary_text: text })
    });
    const j = await r.json().catch(()=>({}));
    if (!r.ok || j?.ok===false) {
      // 정책 위반 피드백
      if (j?.code==='BLOCKED_BY_POLICY' || j?.violations) {
        setBlocked(
          (j?.violations || []).map((v:any)=>`${v.field}: ${v.rule}(${v.snippet||''})`).join(', ') || '정책 차단'
        );
        toast.error('정책 차단: 문구를 수정해 주세요.');
        return;
      }
      toast.error(j?.message||j?.code||`실패(${r.status})`);
      return;
    }
    toast.success('캠페인이 생성되었습니다.');
    location.href='/campaigns';
  };

  return (
    <main style={{maxWidth:640}}>
      <h2>캠페인 생성</h2>
      <input placeholder="캠페인명" value={title} onChange={e=>setTitle(e.target.value)} />
      <textarea placeholder="광고 문구" value={text} onChange={e=>setText(e.target.value)} />
      <button onClick={create}>생성</button>
      {blocked && <p data-testid="policy-block-msg" style={{color:'crimson'}}>{blocked}</p>}
    </main>
  );
}
