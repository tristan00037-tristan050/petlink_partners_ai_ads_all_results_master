-- P0: policy_violations 테이블 생성
-- 정책 위반 기록 (금칙어, AI 심사 결과)

CREATE TABLE IF NOT EXISTS policy_violations (
  id BIGSERIAL PRIMARY KEY,
  campaign_id BIGINT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
    -- KEYWORD: 금칙어
    -- AI_POLICY: AI 심사
  field TEXT NOT NULL,
    -- title, body, hashtags 등
  keyword TEXT,
    -- 금칙어 (type=KEYWORD일 때)
  code TEXT,
    -- AI 정책 코드 (type=AI_POLICY일 때)
    -- 예: SEXUAL_CONTENT, VIOLENCE, etc.
  score NUMERIC(5,2),
    -- AI 점수 (0.0 ~ 1.0, type=AI_POLICY일 때)
  message TEXT NOT NULL,
  suggested_body TEXT,
    -- 제안 문구
  suggested_hashtags TEXT[],
    -- 제안 해시태그 배열
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_policy_violations_campaign_id ON policy_violations(campaign_id);
CREATE INDEX IF NOT EXISTS idx_policy_violations_type ON policy_violations(type);
CREATE INDEX IF NOT EXISTS idx_policy_violations_created_at ON policy_violations(created_at);

COMMENT ON TABLE policy_violations IS '정책 위반 기록 (캠페인 상태 전이 근거)';
COMMENT ON COLUMN policy_violations.type IS '위반 유형: KEYWORD, AI_POLICY';
COMMENT ON COLUMN policy_violations.field IS '위반 필드: title, body, hashtags 등';
COMMENT ON COLUMN policy_violations.score IS 'AI 점수 (0.0 ~ 1.0)';

