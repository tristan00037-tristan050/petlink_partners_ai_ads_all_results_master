export const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:5903';

async function api(path: string, init: RequestInit = {}) {
  const res = await fetch(`${API_BASE}${path}`, {
    credentials: 'include',
    headers: { 'Content-Type': 'application/json', ...(init.headers || {}) },
    ...init,
  });

  const ct = res.headers.get('content-type') || '';
  if (!ct.includes('application/json')) {
    const text = await res.text();
    // 응답이 HTML 등 비-JSON이면 URL/상태와 함께 잘라서 보여줌
    throw new Error(
      `NON_JSON_RESPONSE ${res.status} @ ${API_BASE}${path}\n` +
      String(text).slice(0, 200)
    );
  }

  const json = await res.json();
  if (!res.ok || json?.ok === false) {
    const code = json?.code || `HTTP_${res.status}`;
    throw new Error(code);
  }
  return json;
}

export const get  = (p: string) => api(p);
export const post = (p: string, body?: any) => api(p, { method: 'POST', body: JSON.stringify(body||{}) });
export const patch= (p: string, body?: any) => api(p, { method: 'PATCH', body: JSON.stringify(body||{}) });
export const del  = (p: string) => api(p, { method: 'DELETE' });

