'use client';
import { createContext, useCallback, useContext, useMemo, useState } from 'react';

type Toast = { id:number; kind:'success'|'error'|'info'; msg:string; ttl?:number };
const Ctx = createContext<(t:Omit<Toast,'id'>)=>void>(()=>{});

export function ToastHost() {
  const [list,setList] = useState<Toast[]>([]);
  const push = useCallback((t:Omit<Toast,'id'>)=>{
    const id = Date.now()+Math.random();
    setList(prev=>[...prev,{ id, ...t }]);
    setTimeout(()=>setList(prev=>prev.filter(x=>x.id!==id)), t.ttl ?? 2500);
  },[]);
  const api = useMemo(()=>push,[push]);

  return (
    <Ctx.Provider value={api}>
      <div style={{position:'fixed',right:16,bottom:16,zIndex:9999,display:'flex',flexDirection:'column',gap:8}}>
        {list.map(t=>{
          const bg = t.kind==='success' ? '#2e7d32' : t.kind==='error' ? '#c62828' : '#1565c0';
          return <div key={t.id} style={{background:bg,color:'#fff',padding:'10px 12px',borderRadius:6,minWidth:240}}>{t.msg}</div>;
        })}
      </div>
    </Ctx.Provider>
  );
}
export function useToast(){
  const push = useContext(Ctx);
  // Context가 없을 경우를 대비한 안전한 fallback (기본값이 있지만 추가 안전장치)
  const safePush = push || (() => {});
  return {
    success:(msg:string,ttl?:number)=>safePush({kind:'success',msg,ttl}),
    error:(msg:string,ttl?:number)=>safePush({kind:'error',msg,ttl}),
    info:(msg:string,ttl?:number)=>safePush({kind:'info',msg,ttl}),
  };
}
