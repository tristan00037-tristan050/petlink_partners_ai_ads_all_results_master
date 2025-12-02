/**
 * PolicyEngine - 정책 검증 엔진
 * P0: 룰 기반 필터 + AI 심사 (텍스트 중심)
 */

/**
 * PolicyEngine 결과 스키마
 * @typedef {Object} PolicyResult
 * @property {boolean} approved - 승인 여부
 * @property {string} decision - REJECT|REVIEW|ALLOW
 * @property {Array<PolicyReason>} reasons - 위반 사유 목록
 * @property {string} [suggested_body] - 제안 문구
 * @property {Array<string>} [suggested_hashtags] - 제안 해시태그
 */

/**
 * @typedef {Object} PolicyReason
 * @property {string} type - KEYWORD|AI_POLICY
 * @property {string} field - title|body|hashtags
 * @property {string} [keyword] - 금칙어 (type=KEYWORD일 때)
 * @property {string} [code] - AI 정책 코드 (type=AI_POLICY일 때)
 * @property {number} [score] - AI 점수 (0.0 ~ 1.0)
 * @property {string} message - 위반 메시지
 */

/**
 * 금칙어 목록 (예시)
 * 실제로는 DB 또는 설정 파일에서 로드
 */
const BANNED_KEYWORDS = [
  '도박', '불법', '성인', '학대', '폭력', '마약', '음주',
  // 추가 금칙어...
];

/**
 * AI 정책 임계값
 */
const AI_POLICY_THRESHOLDS = {
  SEXUAL_CONTENT: 0.8,
  VIOLENCE: 0.8,
  HATE_SPEECH: 0.8,
  // 추가 정책...
};

/**
 * PolicyEngine 클래스
 */
class PolicyEngine {
  /**
   * 캠페인 정책 검증
   * @param {Object} campaign - 캠페인 데이터
   * @param {string} campaign.title - 제목
   * @param {string} campaign.body - 본문
   * @param {Array<string>} campaign.hashtags - 해시태그
   * @returns {Promise<PolicyResult>}
   */
  async validate(campaign) {
    const reasons = [];
    let decision = 'ALLOW';
    let approved = true;

    // 1. 룰 기반 필터 (금칙어 검증)
    const keywordViolations = this.checkKeywords(campaign);
    if (keywordViolations.length > 0) {
      reasons.push(...keywordViolations);
      decision = 'REJECT';
      approved = false;
    }

    // 2. AI 심사 (텍스트 중심)
    const aiViolations = await this.checkAIPolicy(campaign);
    if (aiViolations.length > 0) {
      reasons.push(...aiViolations);
      // AI 위반이 있으면 REVIEW 또는 REJECT
      if (decision !== 'REJECT') {
        decision = 'REVIEW';
        approved = false;
      }
    }

    // 3. 제안 문구 생성 (위반이 있을 때)
    let suggested_body = null;
    let suggested_hashtags = null;
    if (reasons.length > 0) {
      suggested_body = this.generateSuggestedBody(campaign.body, reasons);
      suggested_hashtags = this.generateSuggestedHashtags();
    }

    return {
      approved,
      decision,
      reasons,
      suggested_body,
      suggested_hashtags
    };
  }

  /**
   * 금칙어 검증
   * @param {Object} campaign
   * @returns {Array<PolicyReason>}
   */
  checkKeywords(campaign) {
    const violations = [];
    const text = `${campaign.title} ${campaign.body} ${(campaign.hashtags || []).join(' ')}`;

    for (const keyword of BANNED_KEYWORDS) {
      if (text.includes(keyword)) {
        // 어떤 필드에서 발견되었는지 확인
        let field = 'body';
        if (campaign.title.includes(keyword)) {
          field = 'title';
        } else if ((campaign.hashtags || []).some(h => h.includes(keyword))) {
          field = 'hashtags';
        }

        violations.push({
          type: 'KEYWORD',
          field,
          keyword,
          message: `금칙어 사용: "${keyword}"`
        });
      }
    }

    return violations;
  }

  /**
   * AI 정책 검증
   * @param {Object} campaign
   * @returns {Promise<Array<PolicyReason>>}
   */
  async checkAIPolicy(campaign) {
    const violations = [];
    
    // TODO: 실제 AI API 호출 (예: OpenAI, Google Cloud AI)
    // 현재는 모의 구현
    const text = `${campaign.title} ${campaign.body}`;
    
    // 모의 AI 점수 계산 (실제로는 AI API 호출)
    const mockScores = {
      SEXUAL_CONTENT: Math.random() * 0.5, // 0.0 ~ 0.5
      VIOLENCE: Math.random() * 0.5,
      HATE_SPEECH: Math.random() * 0.5
    };

    for (const [code, threshold] of Object.entries(AI_POLICY_THRESHOLDS)) {
      const score = mockScores[code] || 0;
      if (score >= threshold) {
        violations.push({
          type: 'AI_POLICY',
          field: 'body',
          code,
          score,
          message: `AI 정책 위반: ${code} (점수: ${score.toFixed(2)})`
        });
      }
    }

    return violations;
  }

  /**
   * 제안 문구 생성
   * @param {string} originalBody
   * @param {Array<PolicyReason>} reasons
   * @returns {string}
   */
  generateSuggestedBody(originalBody, reasons) {
    // 간단한 제안 문구 생성 (실제로는 더 정교한 로직 필요)
    let suggested = originalBody;
    
    // 금칙어 제거
    for (const reason of reasons) {
      if (reason.type === 'KEYWORD' && reason.keyword) {
        suggested = suggested.replace(new RegExp(reason.keyword, 'g'), '');
      }
    }

    // 기본 안전 문구 추가
    if (suggested.length < 50) {
      suggested += ' 가족에게 책임 있는 만남을 약속드립니다. 방문 상담 환영합니다.';
    }

    return suggested.trim();
  }

  /**
   * 제안 해시태그 생성
   * @returns {Array<string>}
   */
  generateSuggestedHashtags() {
    return [
      '#책임분양',
      '#반려가족',
      '#방문상담',
      '#반려동물',
      '#분양'
    ];
  }
}

module.exports = new PolicyEngine();

