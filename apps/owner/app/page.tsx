import Link from 'next/link';
export default function Home() {
  return (
    <main>
      <h1>Owner Portal</h1>
      <p><Link href="/login">로그인</Link></p>
      <p><Link href="/signup">회원가입</Link></p>
      <p><Link href="/dashboard">대시보드</Link></p>
      <p><Link href="/stores/new">매장 등록</Link></p>
      <p><Link href="/plans">요금제</Link></p>
      <p><Link href="/pets">반려동물</Link></p>
      <p><Link href="/campaigns">캠페인</Link></p>
      <p><Link href="/campaigns/new">캠페인 생성</Link></p>
      <p><Link href="/billing/invoices">인보이스</Link></p>
    </main>
  );
}

