import { NextRequest, NextResponse } from 'next/server';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:5903';
const ADMIN_KEY = process.env.ADMIN_KEY; // server-only

export async function GET(req: NextRequest, { params }: { params: { path: string[] }}) {
  return proxy(req, params);
}
export async function POST(req: NextRequest, { params }: { params: { path: string[] }}) {
  return proxy(req, params);
}
export async function PUT(req: NextRequest, { params }: { params: { path: string[] }}) {
  return proxy(req, params);
}
export async function DELETE(req: NextRequest, { params }: { params: { path: string[] }}) {
  return proxy(req, params);
}

async function proxy(req: NextRequest, params: { path: string[] }) {
  if (!ADMIN_KEY) return NextResponse.json({ ok:false, code:'ADMIN_KEY_MISSING' }, { status:500 });
  const path = params.path.join('/');
  const url = new URL(req.url);
  const qs = url.search ? url.search : '';
  const target = `${API_BASE}/admin/${path}${qs}`;

  const init: RequestInit = {
    method: req.method,
    headers: {
      'X-Admin-Key': ADMIN_KEY,
      'Content-Type': req.headers.get('content-type') || 'application/json',
    },
    body: ['GET','HEAD'].includes(req.method) ? undefined : await req.text(),
  };
  const r = await fetch(target, init);
  const ct = r.headers.get('content-type') || 'application/json';
  const body = await r.text();
  return new NextResponse(body, { status: r.status, headers: { 'content-type': ct }});
}
