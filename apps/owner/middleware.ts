import type { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';

// 보호할 경로만 정확히 매칭
export const config = {
  matcher: [
    '/dashboard/:path*',
    '/stores/:path*',
    '/plans/:path*',
    '/pets/:path*',
    '/campaigns/:path*',
    '/billing/:path*',
  ],
};

export function middleware(req: NextRequest) {
  const session = req.cookies.get('session')?.value;
  if (!session) {
    const url = req.nextUrl.clone();
    url.pathname = '/login';
    url.searchParams.set('next', req.nextUrl.pathname);
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

