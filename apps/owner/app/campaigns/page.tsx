'use client';
import { useEffect, useState } from 'react';
import { API_BASE } from '../../lib/api';
import useStoreSelection from '../../lib/useStoreSelection';
import RequireAuth from '../../components/RequireAuth';

export default function Campaigns() {
  const [stores,setStores]=useState<any[]>([]);
  const { sid, setSid } = useStoreSelection();
  const [items,setItems]=useState<any[]>([]);
  const [statusMap,setStatusMap]=useState<any>({});
  const [blockedMap,setBlockedMap]=useState<any>({});
  const [openHistory,setOpenHistory] = useState<number|null>(null);
  const [history,setHistory] = useState<Record<number, any[]>>({});

  useEffect(()=>{
    (async()=>{
      const s = await fetch(API_BASE + '/stores', { credentials:'include' }).then(r=>r.json());
      setStores(s.items || []); if (!sid && s.items?.[0]) setSid(s.items[0].id);
      const m = await fetch(API_BASE + '/meta/status-map').then(r=>r.json());
      setStatusMap(m?.campaign || {});
      setBlockedMap(m?.blocked || {});
    })();
  // eslint-disable-next-line
  },[]);

  const refresh = async ()=>{
    if (!sid) return;
    const list = await fetch(`${API_BASE}/stores/${sid}/campaigns`, { credentials:'include' }).then(r=>r.json());
    setItems(list.items || []);
  };
  useEffect(()=>{ refresh(); }, [sid]);

  async function loadHistory(id:number){
    try {
      // 1) /campaigns/:id/history 시도
      let r = await fetch(`${API_BASE}/campaigns/${id}/history`, { credentials:'include' });
      if (r.ok) {
        const j = await r.json().catch(()=>({items:[]}));
        history[id] = j.items || j || [];
        setHistory({...history});
        return;
      }
      // 2) /campaigns/:id 에 포함되어 있을 수 있음
      r = await fetch(`${API_BASE}/campaigns/${id}`, { credentials:'include' });
      if (r.ok) {
        const j = await r.json().catch(()=>({}));
        const arr = j?.status_history || [];
        history[id] = Array.isArray(arr) ? arr : [];
        setHistory({...history});
      }
    } catch {/* no-op */}
  }

  const act = async (id:number, action:'activate'|'pause'|'stop')=>{
    const r = await fetch(`${API_BASE}/campaigns/${id}/${action}`, { method:'POST', credentials:'include' });
    const j = await r.json();
    if (j.ok) refresh();
    else {
      if (j.code==='BLOCKED_BY_POLICY') alert(`${blockedMap.policy?.user_hint||'정책 위반으로 차단됨.'}`);
      else if (j.code==='BLOCKED_BY_BILLING') alert(`${blockedMap.billing?.user_hint||'결제 연체로 차단됨.'}`);
      else alert(j.code||'실패');
      refresh();
    }
  };

  return (
    <RequireAuth>
      <main>
        <h2>캠페인</h2>
      <div>
        <label>매장:</label>
        <select value={sid} onChange={e=>setSid(parseInt(e.target.value,10))}>
          {stores.map((s:any)=><option key={s.id} value={s.id}>{s.name}</option>)}
        </select>
      </div>
      <ul style={{marginTop:12}}>
        {items.map((c:any)=>
          <li key={c.id} style={{margin:'8px 0'}}>
            <b>{c.name}</b> — <i>{statusMap[c.status]?.label || c.status}</i>
            {' '}<button onClick={()=>act(c.id,'activate')}>활성</button>
            {' '}<button onClick={()=>act(c.id,'pause')}>일시중지</button>
            {' '}<button onClick={()=>act(c.id,'stop')}>정지</button>
            {' '}<button onClick={async()=>{
              const next = openHistory===c.id ? null : c.id;
              setOpenHistory(next);
              if (next) await loadHistory(c.id);
            }}>
              {openHistory===c.id ? '이력 닫기' : '이력 보기'}
            </button>
            {openHistory===c.id && (
              <div style={{marginTop:8, background:'#fafafa', padding:8}}>
                {(history[c.id]||[]).length ? (
                  <ul>
                    {history[c.id].map((h:any,idx:number)=>(
                      <li key={idx}>
                        {h.changed_at || h.created_at || '-'} — {h.status || h.to || h.event}
                        {h.reason ? ` (${h.reason})` : ''}
                      </li>
                    ))}
                  </ul>
                ) : <small style={{color:'#666'}}>이력 데이터를 표시할 수 없습니다.</small>}
              </div>
            )}
          </li>
        )}
      </ul>
      </main>
    </RequireAuth>
  );
}

