import { NextRequest, NextResponse } from 'next/server';

export async function POST(req: NextRequest) {
  try {
    const { email, password } = await req.json();

    // 백엔드 로그인 호출 (5903)
    const be = await fetch(`${process.env.NEXT_PUBLIC_API_BASE}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    });

    const data = await be.json().catch(() => ({}));

    if (!be.ok || !data?.token) {
      return NextResponse.json(
        { ok: false, message: data?.message ?? 'LOGIN_FAILED' },
        { status: 401 }
      );
    }

    // Owner(3003) 오리진에 세션 쿠키 직접 발급
    const res = NextResponse.json({ ok: true }, { status: 200 });
    res.cookies.set('session', data.token, {
      httpOnly: true,
      sameSite: 'lax',
      secure: process.env.NODE_ENV === 'production',
      path: '/',
      maxAge: 60 * 60 * 24 * 7, // 7일
    });

    return res;
  } catch (e) {
    return NextResponse.json({ ok: false, message: 'BFF_ERROR' }, { status: 500 });
  }
}
