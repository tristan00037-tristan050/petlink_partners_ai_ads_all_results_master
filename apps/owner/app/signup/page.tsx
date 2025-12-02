'use client';

import { useRouter, useSearchParams } from 'next/navigation';
import { useState } from 'react';
import Link from 'next/link';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:5903';

export default function SignupPage() {
  const router = useRouter();
  const sp = useSearchParams();
  const [email, setEmail] = useState('');
  const [pw, setPw] = useState('');
  const [tenant, setTenant] = useState('default');
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setErr(null);
    
    if (pw.length < 8) {
      setErr('비밀번호는 8자 이상이어야 합니다.');
      return;
    }
    
    setLoading(true);
    
    try {
      // 1) 백엔드 회원가입
      const r1 = await fetch(`${process.env.NEXT_PUBLIC_API_BASE}/auth/signup`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password: pw }),
      });

      const j1 = await r1.json().catch(() => ({}));
      if (!r1.ok) {
        alert(j1?.message ?? 'SIGNUP_FAILED');
        setLoading(false);
        return;
      }

      // 2) BFF 자동 로그인 (★ include 필수)
      const r2 = await fetch('/bff/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ email, password: pw }),
      });

      const j2 = await r2.json().catch(() => ({}));
      if (!r2.ok || !j2?.ok) {
        // 실패 시 로그인 화면으로 유도
        const next = sp.get('next') ?? '/dashboard';
        router.replace(`/login?next=${encodeURIComponent(next)}`);
        setLoading(false);
        return;
      }

      // 3) 대시보드 이동 (SSR 미들웨어 통과)
      const next = sp.get('next') ?? '/dashboard';
      router.replace(next);
    } catch (e: any) {
      setErr(e?.message || '알 수 없는 오류');
      setLoading(false);
    }
  }

  return (
    <main style={{ maxWidth: 420, margin: '40px auto', padding: '20px' }}>
      <h2>회원가입</h2>
      <form onSubmit={submit}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
          <input
            placeholder="이메일"
            type="email"
            value={email}
            onChange={e => setEmail(e.target.value)}
            disabled={loading}
            required
            style={{ padding: '10px', fontSize: '16px' }}
          />
          <input
            placeholder="비밀번호(8자 이상)"
            type="password"
            value={pw}
            onChange={e => setPw(e.target.value)}
            disabled={loading}
            required
            minLength={8}
            style={{ padding: '10px', fontSize: '16px' }}
          />
          <input
            placeholder="테넌트"
            value={tenant}
            onChange={e => setTenant(e.target.value)}
            disabled={loading}
            style={{ padding: '10px', fontSize: '16px' }}
          />
          <button
            type="submit"
            disabled={loading}
            style={{
              padding: '12px',
              fontSize: '16px',
              backgroundColor: loading ? '#ccc' : '#0070f3',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: loading ? 'not-allowed' : 'pointer'
            }}
          >
            {loading ? '진행 중...' : '가입하기'}
          </button>
          {err && <p style={{ color: 'crimson', marginTop: 8 }}>{err}</p>}
          <p style={{ marginTop: 12, textAlign: 'center', color: '#666' }}>
            이미 계정이 있으신가요? <Link href="/login" style={{ color: '#0070f3' }}>로그인으로 이동</Link>
          </p>
        </div>
      </form>
    </main>
  );
}
