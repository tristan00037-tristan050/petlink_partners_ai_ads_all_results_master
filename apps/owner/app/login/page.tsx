'use client';
import { useState } from 'react';
import Link from 'next/link';
import { API_BASE } from '../../lib/api';

export default function Login() {
  const [email,setEmail]=useState(''); const [password,setPassword]=useState('');
  const submit = async () => {
    try {
      const r = await fetch(API_BASE + '/bff/login', {
        method:'POST', 
        credentials:'include',  // 쿠키 전송 필수
        headers:{'Content-Type':'application/json'},
        body: JSON.stringify({ email, password })
      });
      if (r.ok) {
        // 로그인 성공 - 쿠키가 설정되었으므로 대시보드로 이동
        location.href='/dashboard';
      } else {
        const data = await r.json().catch(() => ({}));
        alert(data.message || '로그인 실패');
      }
    } catch (err: any) {
      console.error('Login error:', err);
      alert('로그인 중 오류가 발생했습니다: ' + (err.message || '알 수 없는 오류'));
    }
  };
  return (
    <main style={{maxWidth:420, margin: '40px auto', padding: '20px'}}>
      <h2>로그인</h2>
      <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        <input
          placeholder="이메일"
          value={email}
          onChange={e=>setEmail(e.target.value)}
          style={{ padding: '10px', fontSize: '16px' }}
          onKeyPress={e => {
            if (e.key === 'Enter') submit();
          }}
        />
        <input
          placeholder="비밀번호"
          type="password"
          value={password}
          onChange={e=>setPassword(e.target.value)}
          style={{ padding: '10px', fontSize: '16px' }}
          onKeyPress={e => {
            if (e.key === 'Enter') submit();
          }}
        />
        <button
          onClick={submit}
          style={{
            padding: '12px',
            fontSize: '16px',
            backgroundColor: '#0070f3',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer'
          }}
        >
          로그인
        </button>
      </div>
      <p style={{ marginTop: '20px', textAlign: 'center', color: '#666' }}>
        계정이 없으신가요?{' '}
        <Link href="/signup" style={{ color: '#0070f3' }}>회원가입</Link>
      </p>
    </main>
  );
}

