const express = require('express');
const db = require('../lib/db');
const fs = require('fs');
const path = require('path');
const r = express.Router();

// 금칙어 로드
let bannedWords = [];
try {
  const banwordsPath = path.join(__dirname, '../../config/banwords_ko.txt');
  if (fs.existsSync(banwordsPath)) {
    bannedWords = fs.readFileSync(banwordsPath, 'utf8')
      .split('\n')
      .map(w => w.trim())
      .filter(w => w && !w.startsWith('#'));
  }
} catch (e) {
  console.warn('[validate] banwords load failed:', e.message);
}

// 금지 키워드 패턴 로드
let bannedPatterns = {};
try {
  const bannedPath = path.join(__dirname, '../../policy/banned_keywords.json');
  if (fs.existsSync(bannedPath)) {
    const banned = JSON.parse(fs.readFileSync(bannedPath, 'utf8'));
    bannedPatterns = banned.categories || {};
  }
} catch (e) {
  console.warn('[validate] banned_keywords load failed:', e.message);
}

// 채널별 길이 제한
const CHANNEL_LIMITS = {
  META: { text: 125, hashtags: 30, links: 1 },
  YOUTUBE: { text: 100, hashtags: 0, links: 1 },
  KAKAO: { text: 200, hashtags: 0, links: 0 },
  NAVER: { text: 150, hashtags: 10, links: 1 }
};

// 텍스트 길이 검증
function validateLength(text, channel) {
  const limit = CHANNEL_LIMITS[channel]?.text || 200;
  if (text.length > limit) {
    return {
      type: 'LENGTH',
      severity: 'error',
      message: `텍스트가 ${limit}자 제한을 초과했습니다 (${text.length}자)`,
      limit,
      actual: text.length
    };
  }
  return null;
}

// 금칙어 검사
function validateBannedWords(text) {
  const issues = [];
  const lowerText = text.toLowerCase();
  
  for (const word of bannedWords) {
    if (word && lowerText.includes(word.toLowerCase())) {
      const pos = lowerText.indexOf(word.toLowerCase());
      issues.push({
        type: 'BANNED_WORD',
        severity: 'error',
        word,
        position: pos,
        message: `금칙어 "${word}" 발견`
      });
    }
  }
  
  return issues;
}

// 금지 패턴 검사
function validateBannedPatterns(text) {
  const issues = [];
  
  for (const [category, rules] of Object.entries(bannedPatterns)) {
    if (!rules.keywords && !rules.patterns) continue;
    
    // 키워드 검사
    if (rules.keywords) {
      for (const keyword of rules.keywords) {
        if (text.includes(keyword)) {
          issues.push({
            type: 'BANNED_PATTERN',
            severity: 'warn',
            category,
            keyword,
            message: `${rules.description || category} 관련 표현 "${keyword}" 발견`
          });
        }
      }
    }
    
    // 패턴 검사
    if (rules.patterns) {
      for (const pattern of rules.patterns) {
        try {
          const regex = new RegExp(pattern, 'gi');
          if (regex.test(text)) {
            issues.push({
              type: 'BANNED_PATTERN',
              severity: 'warn',
              category,
              pattern,
              message: `${rules.description || category} 관련 패턴 발견`
            });
          }
        } catch (e) {
          // 잘못된 정규식 무시
        }
      }
    }
  }
  
  return issues;
}

// 해시태그 검증
function validateHashtags(hashtags, channel) {
  const issues = [];
  const limit = CHANNEL_LIMITS[channel]?.hashtags || 0;
  
  if (hashtags.length > limit) {
    issues.push({
      type: 'HASHTAG_LIMIT',
      severity: 'error',
      message: `해시태그가 ${limit}개 제한을 초과했습니다 (${hashtags.length}개)`,
      limit,
      actual: hashtags.length
    });
  }
  
  // 해시태그 형식 검증
  for (let i = 0; i < hashtags.length; i++) {
    const tag = hashtags[i];
    if (!tag.startsWith('#')) {
      issues.push({
        type: 'HASHTAG_FORMAT',
        severity: 'error',
        message: `해시태그 "${tag}"는 #으로 시작해야 합니다`,
        tag,
        index: i
      });
    }
    if (tag.length > 30) {
      issues.push({
        type: 'HASHTAG_LENGTH',
        severity: 'warn',
        message: `해시태그 "${tag}"가 너무 깁니다 (30자 제한)`,
        tag,
        length: tag.length
      });
    }
  }
  
  return issues;
}

// 링크 검증
function validateLinks(links, channel) {
  const issues = [];
  const limit = CHANNEL_LIMITS[channel]?.links || 0;
  
  if (links.length > limit) {
    issues.push({
      type: 'LINK_LIMIT',
      severity: 'error',
      message: `링크가 ${limit}개 제한을 초과했습니다 (${links.length}개)`,
      limit,
      actual: links.length
    });
  }
  
  // URL 형식 검증
  const urlPattern = /^https?:\/\/.+/;
  for (let i = 0; i < links.length; i++) {
    const link = links[i];
    if (!urlPattern.test(link)) {
      issues.push({
        type: 'LINK_FORMAT',
        severity: 'error',
        message: `링크 "${link}"가 올바른 URL 형식이 아닙니다`,
        link,
        index: i
      });
    }
  }
  
  return issues;
}

// 점수 계산 (0.0 ~ 1.0)
function calculateScore(issues) {
  const errorCount = issues.filter(i => i.severity === 'error').length;
  const warnCount = issues.filter(i => i.severity === 'warn').length;
  
  // 에러 1개당 -0.3, 경고 1개당 -0.1
  const score = Math.max(0, 1.0 - (errorCount * 0.3) - (warnCount * 0.1));
  return Math.round(score * 100) / 100;
}

/** POST /ads/validate */
r.post('/validate', express.json(), async (req, res) => {
  try {
    const { advertiser_id, channel, text, hashtags = [], links = [] } = req.body || {};
    
    if (!advertiser_id || !channel || !text) {
      return res.status(400).json({ ok: false, code: 'FIELDS_REQUIRED' });
    }
    
    if (!CHANNEL_LIMITS[channel]) {
      return res.status(400).json({ ok: false, code: 'INVALID_CHANNEL', channels: Object.keys(CHANNEL_LIMITS) });
    }
    
    const issues = [];
    
    // 길이 검증
    const lengthIssue = validateLength(text, channel);
    if (lengthIssue) issues.push(lengthIssue);
    
    // 금칙어 검사
    issues.push(...validateBannedWords(text));
    
    // 금지 패턴 검사
    issues.push(...validateBannedPatterns(text));
    
    // 해시태그 검증
    if (hashtags.length > 0) {
      issues.push(...validateHashtags(hashtags, channel));
    }
    
    // 링크 검증
    if (links.length > 0) {
      issues.push(...validateLinks(links, channel));
    }
    
    const score = calculateScore(issues);
    const valid = issues.filter(i => i.severity === 'error').length === 0;
    
    res.json({
      ok: true,
      valid,
      score,
      issues,
      channel,
      summary: {
        total_issues: issues.length,
        errors: issues.filter(i => i.severity === 'error').length,
        warnings: issues.filter(i => i.severity === 'warn').length
      }
    });
  } catch (e) {
    console.error('[validate] error:', e);
    res.status(500).json({ ok: false, code: 'VALIDATION_ERROR', error: String(e.message || e) });
  }
});

/** POST /ads/autofix - 자동 수정 (간단한 구현) */
r.post('/autofix', express.json(), async (req, res) => {
  try {
    const { advertiser_id, channel, text, hashtags = [], links = [] } = req.body || {};
    
    if (!advertiser_id || !channel || !text) {
      return res.status(400).json({ ok: false, code: 'FIELDS_REQUIRED' });
    }
    
    if (!CHANNEL_LIMITS[channel]) {
      return res.status(400).json({ ok: false, code: 'INVALID_CHANNEL', channels: Object.keys(CHANNEL_LIMITS) });
    }
    
    let fixedText = text;
    const limit = CHANNEL_LIMITS[channel]?.text || 200;
    
    // 길이 자동 축약
    if (fixedText.length > limit) {
      fixedText = fixedText.slice(0, limit);
    }
    
    // 금칙어 제거
    for (const word of bannedWords) {
      if (word) {
        const regex = new RegExp(word, 'gi');
        fixedText = fixedText.replace(regex, '');
      }
    }
    fixedText = fixedText.trim();
    
    // 해시태그 정리
    let fixedHashtags = Array.isArray(hashtags) ? hashtags.filter(Boolean) : [];
    fixedHashtags = fixedHashtags
      .map(tag => tag.startsWith('#') ? tag : '#' + tag)
      .slice(0, CHANNEL_LIMITS[channel]?.hashtags || 0);
    
    // 링크 정리
    let fixedLinks = Array.isArray(links) ? links.filter(Boolean) : [];
    fixedLinks = fixedLinks.slice(0, CHANNEL_LIMITS[channel]?.links || 0);
    
    // 수정 여부 확인
    const patched = fixedText !== text || 
                    JSON.stringify(fixedHashtags) !== JSON.stringify(hashtags) ||
                    JSON.stringify(fixedLinks) !== JSON.stringify(links);
    
    res.json({
      ok: true,
      patched,
      fixed_text: fixedText,
      fixed_hashtags: fixedHashtags,
      fixed_links: fixedLinks,
      result: {
        advertiser_id,
        channel,
        text: fixedText,
        hashtags: fixedHashtags,
        links: fixedLinks
      }
    });
  } catch (e) {
    console.error('[autofix] error:', e);
    res.status(500).json({ ok: false, code: 'AUTOFIX_ERROR', error: String(e.message || e) });
  }
});

module.exports = r;
