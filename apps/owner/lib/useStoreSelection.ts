'use client';
import { useEffect, useState } from 'react';

const KEY = 'owner.selectedStoreId';

export function useStoreSelection(){
  const [storeId,setStoreId] = useState<string|undefined>(undefined);
  useEffect(()=>{
    const v = typeof window!=='undefined' ? window.localStorage.getItem(KEY) : null;
    if (v) setStoreId(v);
  },[]);
  const select = (id:string)=>{
    setStoreId(id);
    if (typeof window!=='undefined') window.localStorage.setItem(KEY, id);
  };
  return { storeId, setStoreId: select };
}
