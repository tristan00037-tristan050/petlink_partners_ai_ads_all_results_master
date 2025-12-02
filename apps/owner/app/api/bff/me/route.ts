import { NextRequest, NextResponse } from 'next/server';

export async function GET(req: NextRequest) {
  const session = req.cookies.get('session')?.value;
  
  if (!session) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }

  // (선택) 서명검증/JWT 검증 또는 백엔드 /auth/me 프록시
  // 실제 구현에서는 세션 검증 로직 추가 필요
  const ok = true; // 실제 검증 결과로 대체
  
  if (!ok) {
    return NextResponse.json({ ok: false }, { status: 401 });
  }

  return NextResponse.json({ ok: true, user: { /* ... */ } }, { status: 200 });
}


