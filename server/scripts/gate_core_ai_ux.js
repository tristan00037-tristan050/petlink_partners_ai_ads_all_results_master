const fs = require('fs');

const ban = fs.readFileSync('config/banwords_ko.txt','utf8')
  .split('\n').map(s=>s.trim()).filter(Boolean);

const CH_RULE = {
  META:    (s)=> s.length<=125,
  YOUTUBE: (s)=> s.length<=100 && /[|·]/.test(s),
  KAKAO:   (s)=> s.length<=100 && /(상담|문의|예약)/.test(s),
  NAVER:   (s)=> s.length<=80  && /(안내)/.test(s),
};

const samples = [];
const base = [
  '상담/방문 안내 – 오늘도 반려동물 케어', 
  '문의 환영 – 빠른 예약 도와드립니다',
  '매장 이벤트 알림 – 간단한 신청만으로 참여',
  '방문 전 주차/운영시간 안내',
  '광고 운영 리포트 제공 – 투명한 집행'
];
// 채널별 5개씩 총 20개
['META','YOUTUBE','KAKAO','NAVER'].forEach((ch,i)=>{
  for(let k=0;k<5;k++){
    let t = base[(i+k)%base.length];
    if(ch==='YOUTUBE') t = `가이드 | ${t}`;
    if(ch==='KAKAO')   t = `상담 안내: ${t}`;
    if(ch==='NAVER')   t = `안내: ${t.slice(0,50)}`;
    samples.push({ch, text: t});
  }
});

// 금칙어 검사
let bad=0;
for(const {text} of samples){
  const hit = ban.some(w => w && text.includes(w));
  if(hit) bad++;
}

// 포맷 적합
let ok=0;
for(const {ch,text} of samples){
  const f = CH_RULE[ch] || ((s)=>s.length>0);
  if(f(text)) ok++;
}

const rate = Math.round((ok/samples.length)*100);
console.log(`GATE-1.BANWORDS=${bad}`);
console.log(`GATE-1.FORMAT_RATE=${rate}`);
