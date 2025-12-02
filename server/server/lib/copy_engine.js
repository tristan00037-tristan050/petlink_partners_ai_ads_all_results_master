// 금칙어 필터 고도화 (H1) - 띄어쓰기/이모지 변형 차단
const BANNED = [
    /가 ?격/i,
    /재 ?고/i,
    /즉시\s?(분양|구매)/i,
    /(택배|배송)/i,
    /(특가|할인\s?판매)/i
];

const normalize = (s) => (s || '').normalize('NFKC').replace(/\p{Emoji_Presentation}/gu, '').replace(/\s+/g, '');

exports.checkCopy = (text = '') => {
    const n = normalize(text);
    const hit = BANNED.find(r => r.test(n));
    return hit ? { ok: false, message: '정책상 금지 표현이 포함되었습니다.' } : { ok: true };
};

exports.suggestCopy = () => '상담/방문 안내 중심으로 작성해 주세요. 예) 방문 상담, 전화 문의, 카카오톡 채널로 안내드립니다.';


