import Link from 'next/link';

export default function NotFound() {
  return (
    <main style={{maxWidth:680, margin:'0 auto', padding:16, textAlign:'center'}}>
      <h2>404 - 페이지를 찾을 수 없습니다</h2>
      <p style={{color:'#666', marginTop:8}}>요청하신 페이지가 존재하지 않습니다.</p>
      <Link href="/dashboard" style={{display:'inline-block', marginTop:16, padding:'8px 16px', background:'#0070f3', color:'white', textDecoration:'none', borderRadius:4}}>
        대시보드로 돌아가기
      </Link>
    </main>
  );
}

