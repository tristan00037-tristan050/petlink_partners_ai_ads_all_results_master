import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest) {
  try {
    const { email, password } = await req.json();

    // 1) 백엔드 로그인 호출 (5903)
    const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:5903';
    const be = await fetch(`${API_BASE}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      // 백엔드 쿠키는 신경쓰지 않습니다. 토큰만 받습니다.
      body: JSON.stringify({ email, password }),
    });

    // 응답이 JSON인지 확인
    const contentType = be.headers.get('content-type') || '';
    let data: any = {};
    
    if (contentType.includes('application/json')) {
      data = await be.json();
    } else {
      // HTML 응답인 경우 (에러 페이지)
      const text = await be.text();
      console.error('Backend returned non-JSON:', text.substring(0, 200));
      return NextResponse.json({ 
        ok: false, 
        message: `LOGIN_FAILED: Backend returned ${be.status}` 
      }, { status: 401 });
    }

    // 백엔드 응답 형식 확인: token 또는 다른 필드명일 수 있음
    const token = data?.token || data?.access_token || data?.session_token || data?.jwt;
    
    if (!be.ok || !token) {
      return NextResponse.json({ 
        ok: false, 
        message: data?.message ?? data?.code ?? 'LOGIN_FAILED' 
      }, { status: 401 });
    }

    // 2) Owner(3003) 도메인에 "session" 쿠키 직접 발급
    const res = NextResponse.json({ ok: true }, { status: 200 });
    res.cookies.set('session', token, {
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      path: '/',
      maxAge: 60 * 60 * 24 * 7, // 7d
    });
    return res;
  } catch (e: any) {
    console.error('BFF login error:', e);
    return NextResponse.json({ 
      ok: false, 
      message: `BFF_ERROR: ${e?.message || 'Unknown error'}` 
    }, { status: 500 });
  }
}
