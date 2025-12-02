'use client';
import Link from 'next/link';
import { API_BASE } from '../lib/api';

export default function Nav() {
  const logout = async () => {
    await fetch(API_BASE + '/bff/logout', { method:'POST', credentials:'include' });
    location.href = '/login';
  };
  return (
    <nav style={{display:'flex', gap:12, margin:'12px 0'}}>
      <Link href="/dashboard">대시보드</Link>
      <Link href="/stores/new">매장 등록</Link>
      <Link href="/plans">요금제</Link>
      <Link href="/pets">반려동물</Link>
      <Link href="/campaigns">캠페인</Link>
      <Link href="/campaigns/new">캠페인 생성</Link>
      <Link href="/billing/invoices">인보이스</Link>
      <button onClick={logout} style={{marginLeft:'auto'}}>로그아웃</button>
    </nav>
  );
}

