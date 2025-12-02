const express = require('express');
const db = require('../lib/db');
const router = express.Router();

// 내부 금칙 정규식(환경변수로 재정의 가능)
const forb = (process.env.FORBIDDEN_PATTERNS || '무료|공짜|100%\\s*보장').split('|');
const reForb = new RegExp('(' + forb.join('|') + ')', 'i');
const reLink = /https?:\/\/\S+/ig;
const reHashtag = /#([A-Za-z가-힣0-9_]{1,30})/g;

async function loadRules(channel){
  const ch = String(channel||'').toUpperCase();
  // 1) channel_rules ACTIVE 우선
  try {
    const a = await db.q("SELECT config FROM channel_rules WHERE channel=$1 AND status='ACTIVE' ORDER BY rule_version DESC LIMIT 1", [ch]);
    if(a.rows.length) {
      const cfg=a.rows[0].config||{}; 
      return { 
        max_len_headline:Number(cfg.max_len_headline||30), 
        max_len_body:Number(cfg.max_len_body||140), 
        max_hashtags:Number(cfg.max_hashtags||10), 
        allow_links:!!cfg.allow_links 
      };
    }
  } catch(e) { /* fallback */ }
  // 2) 기존 channel_rules 테이블 fallback
  try {
    const b = await db.q('SELECT max_len_headline,max_len_body,max_hashtags,allow_links FROM channel_rules WHERE channel=$1 LIMIT 1',[ch]);
    if(b.rows.length){ return b.rows[0]; }
  } catch(e) { /* no-op */ }
  return { max_len_headline:30, max_len_body:140, max_hashtags:10, allow_links:true };
}

function assess({headline='', body='', hashtags=[], links=[]}, rules){
  const issues = [];
  const lenH = headline.trim().length;
  const lenB = body.trim().length;
  if(rules?.max_len_headline && lenH > rules.max_len_headline) issues.push({code:'LEN_HEADLINE', cur:lenH, max:rules.max_len_headline});
  if(rules?.max_len_body && lenB > rules.max_len_body) issues.push({code:'LEN_BODY', cur:lenB, max:rules.max_len_body});
  if(reForb.test(headline) || reForb.test(body)) issues.push({code:'FORBIDDEN'});
  if(!rules?.allow_links && reLink.test(body)) issues.push({code:'LINK_NOT_ALLOWED'});
  if(hashtags && rules?.max_hashtags && hashtags.length > rules.max_hashtags) issues.push({code:'HASHTAG_EXCESS', cur:hashtags.length, max:rules.max_hashtags});
  // 상태 결정
  const red = issues.find(x=> ['FORBIDDEN'].includes(x.code));
  const yellow = issues.length>0 && !red;
  const status = red? 'RED' : (yellow? 'YELLOW':'GREEN');
  return { status, issues };
}

// POST /ads/validate { channel, headline, body, hashtags[], links[] }
router.post('/validate', express.json(), async (req,res)=>{
  const { channel='NAVER', headline='', body='', hashtags=[], links=[] } = req.body || {};
  const rules = await loadRules(channel);
  const r = assess({headline, body, hashtags, links}, rules);
  return res.json({ ok:true, channel, rules, ...r });
});

// POST /ads/autofix { channel, headline, body, hashtags[], links[] }
router.post('/autofix', express.json(), async (req,res)=>{
  const { channel='NAVER', headline='', body='', hashtags=[], links=[] } = req.body || {};
  const rules = await loadRules(channel);
  // 기본 수정 규칙: 금칙어 제거, 길이 자르기, 해시태그/링크 제한
  let H = String(headline||'').replace(reForb,'').trim();
  let B = String(body||'').replace(reForb,'').trim();
  if(rules?.max_len_headline) H = H.slice(0, rules.max_len_headline);
  if(rules?.max_len_body)     B = B.slice(0, rules.max_len_body);
  let tags = Array.isArray(hashtags)? hashtags.filter(Boolean):[];
  tags = tags.map(t=> t.startsWith('#')? t : ('#'+t)).slice(0, rules?.max_hashtags ?? tags.length);
  let L = Array.isArray(links)? links.filter(Boolean):[];
  if(rules && rules.allow_links === false){ L = []; B = B.replace(reLink,''); }
  // 포맷터 적용(채널별)
  let formatted={headline:H, body:B, hashtags:tags, links:L};
  if(channel.toUpperCase()==='NAVER'){ formatted = require('../lib/formatters/naver').format(formatted, rules); }
  if(channel.toUpperCase()==='INSTAGRAM'){ formatted = require('../lib/formatters/instagram').format(formatted, rules); }
  const assessAfter = assess(formatted, rules);
  return res.json({ ok:true, channel, fixed: formatted, assessment: assessAfter, applied: { forb_removed:true, len_clamped:true, tag_clamped:true, links_policy: rules?.allow_links!==false } });
});

module.exports = router;
