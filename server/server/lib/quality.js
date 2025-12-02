/**
 * 간단 검증/자동수정 규칙
 * - 길이 제한: 채널별 maxChars
 * - 금칙어: FORBIDDEN_PATTERNS (정규식 | 로 구분)
 * - 해시태그 수 제한, 링크 수 제한
 */
const patStr = process.env.FORBIDDEN_PATTERNS || '무료|공짜|100%\\s*보장|전액환불';
const forbRe = new RegExp(`(?:${patStr})`, 'i');

function countHashtags(txt){ return (txt.match(/#[^\s#]+/g)||[]).length; }
function countLinks(txt){ return (txt.match(/https?:\/\//g)||[]).length; }

function limits(channel='NAVER'){
  const m = { NAVER:{maxChars:1000,maxHashtags:10,maxLinks:1}, INSTAGRAM:{maxChars:2200,maxHashtags:30,maxLinks:1} };
  return m[(channel||'NAVER').toUpperCase()] || m.NAVER;
}

function validate({ text='', channel='NAVER' }){
  const L = limits(channel);
  const errors=[];
  const trimmed = String(text||'').trim();
  if(trimmed.length > L.maxChars) errors.push('LENGTH_EXCEED');
  if(forbRe.test(trimmed)) errors.push('FORBIDDEN');
  if(countHashtags(trimmed) > L.maxHashtags) errors.push('HASHTAG_EXCEED');
  if(countLinks(trimmed) > L.maxLinks) errors.push('LINK_EXCEED');

  const autoApprove = errors.length===0;
  const level = autoApprove ? 'GREEN' : (errors.length<=1 ? 'YELLOW' : 'RED');
  return { ok:true, autoApprove, level, errors, text: trimmed };
}

function autofix({ text='', channel='NAVER' }){
  const L = limits(channel);
  let s = String(text||'').trim();

  // 금칙어 마스킹
  s = s.replace(forbRe, '***');
  // 링크 1개 초과 제거
  const urls = s.match(/https?:\/\/[\w\-._~:/?#\[\]@!$&'()*+,;=%]+/g)||[];
  if(urls.length > L.maxLinks){
    s = s.replace(urls.slice(1).join('|'), '');
  }
  // 해시태그 초과 절단
  const tags = s.match(/#[^\s#]+/g)||[];
  if(tags.length > L.maxHashtags){
    const keep = new Set(tags.slice(0,L.maxHashtags));
    s = s.replace(/#[^\s#]+/g, t => keep.has(t)?t:'');
  }
  // 길이 제한 절단
  if(s.length > L.maxChars) s = s.slice(0, L.maxChars);

  return { ok:true, text:s };
}

module.exports = { validate, autofix };
