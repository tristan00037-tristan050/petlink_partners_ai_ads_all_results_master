"use client";

import { useState } from 'react';

const API_BASE = process.env.NEXT_PUBLIC_API_BASE || 'http://localhost:5903';

export default function NewStorePage() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (loading) return;

    setError(null);
    setLoading(true);

    try {
      const fd = new FormData(e.currentTarget);
      const payload = Object.fromEntries(fd.entries());

      const res = await fetch(`${API_BASE}/stores`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include',                      // ★ 인증 포함
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const j = await res.json().catch(() => ({}));
        setError(j?.message || '매장 생성에 실패했습니다.');
        return;
      }

      const j = await res.json().catch(() => ({}));
      // ★ 응답 형태 방어적 파싱
      const newStoreId =
        j?.id ??
        j?.store?.id ??
        j?.data?.id ??
        j?.result?.id ??
        null;

      if (newStoreId) {
        // 키 호환성 보장: owner.selectedStoreId 우선
        try {
          const state = localStorage.getItem('ownerState');
          const prev = state ? JSON.parse(state) : {};
          localStorage.setItem('ownerState', JSON.stringify({ ...prev, selectedStoreId: newStoreId }));
          localStorage.setItem('owner.selectedStoreId', String(newStoreId));
        } catch {}
      }

      // UI 하드 이동은 유지하되, E2E는 별도 주도 이동으로 처리
      window.location.assign('/plans');
      return;
    } catch (err) {
      console.error('STORE_CREATE_ERROR', err);
      setError('요청 처리 중 오류가 발생했습니다.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="max-w-xl mx-auto p-6 bg-white rounded-xl shadow-lg mt-10">
      <h1 className="text-3xl font-bold text-gray-800 mb-6 text-center">새 매장 등록</h1>
      <form onSubmit={handleSubmit} className="space-y-4" noValidate>
        {error && (
          <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded" role="alert">
            {error}
          </div>
        )}

        <input name="name" placeholder="매장명" required className="w-full px-3 py-2 border rounded" />
        <input name="address" placeholder="주소" required className="w-full px-3 py-2 border rounded" />
        <input name="phone" placeholder="연락처" required className="w-full px-3 py-2 border rounded" />
        <textarea name="description" placeholder="설명" className="w-full px-3 py-2 border rounded" rows={3} />

        <button
          type="submit"
          disabled={loading}
          data-testid="store-submit"                          // ★ 테스트 고정 셀렉터
          className={`w-full py-2 px-4 rounded text-white ${loading ? 'bg-indigo-400' : 'bg-indigo-600 hover:bg-indigo-700'}`}
        >
          {loading ? '등록 중…' : '등록'}
        </button>
      </form>
    </div>
  );
}
