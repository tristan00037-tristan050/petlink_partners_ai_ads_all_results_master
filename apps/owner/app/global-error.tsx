'use client';

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html lang="ko">
      <body>
        <main style={{maxWidth:680, margin:'0 auto', padding:16}}>
          <h2>심각한 오류가 발생했습니다</h2>
          <p style={{color:'#666'}}>{error.message || '알 수 없는 오류가 발생했습니다.'}</p>
          <button onClick={reset} style={{marginTop:12, padding:'8px 16px'}}>
            다시 시도
          </button>
        </main>
      </body>
    </html>
  );
}

