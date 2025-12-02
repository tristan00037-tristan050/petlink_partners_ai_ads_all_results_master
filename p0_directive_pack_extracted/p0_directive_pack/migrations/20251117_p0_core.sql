-- P0 Core DDL - PostgreSQL
-- 날짜: 2025-11-17
-- 범위: users, stores, plans, store_plan_subscriptions, pets, campaigns, creatives, policy_violations

-- ============================================================================
-- 1. 사용자 (users)
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  name VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- ============================================================================
-- 2. 매장 (stores)
-- ============================================================================
CREATE TABLE IF NOT EXISTS stores (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  address TEXT,
  phone VARCHAR(20),
  business_hours TEXT,
  short_description TEXT NOT NULL,
  description TEXT,
  images TEXT[],
  is_complete BOOLEAN DEFAULT false,
    -- 필수 필드 완성 여부: name, short_description, images(≥1)
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stores_user_id ON stores(user_id);
CREATE INDEX IF NOT EXISTS idx_stores_is_complete ON stores(is_complete);

-- updated_at 자동 갱신
CREATE OR REPLACE FUNCTION update_stores_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_stores_updated_at
  BEFORE UPDATE ON stores
  FOR EACH ROW
  EXECUTE FUNCTION update_stores_updated_at();

-- ============================================================================
-- 3. 요금제 (plans)
-- ============================================================================
CREATE TABLE IF NOT EXISTS plans (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(50) NOT NULL UNIQUE,
    -- S, M, L
  name VARCHAR(100) NOT NULL,
    -- Starter, Standard, Pro
  price INTEGER NOT NULL,
    -- 월 요금 (원)
  ad_budget INTEGER NOT NULL,
    -- 광고비 포함액 (원)
  features TEXT[],
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 기본 요금제 데이터
INSERT INTO plans (code, name, price, ad_budget, features) VALUES
  ('S', 'Starter', 200000, 120000, ARRAY['페이스북/인스타그램 또는 틱톡 중 택1', '기본 리포트']),
  ('M', 'Standard', 400000, 300000, ARRAY['페이스북/인스타그램 + 틱톡', '고급 리포트']),
  ('L', 'Pro', 800000, 600000, ARRAY['페이스북/인스타그램 + 틱톡', '프리미엄 리포트'])
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- 4. 매장 요금제 구독 (store_plan_subscriptions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS store_plan_subscriptions (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES plans(id),
  status TEXT NOT NULL DEFAULT 'ACTIVE',
    -- ACTIVE: 정상
    -- OVERDUE: 미납
    -- CANCELLED: 취소
  cycle_start DATE NOT NULL,
  cycle_end DATE NOT NULL,
  next_billing_date DATE NOT NULL,
  last_paid_at TIMESTAMPTZ,
  grace_period_days INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(store_id)
);

CREATE INDEX IF NOT EXISTS idx_store_plan_subscriptions_store_id ON store_plan_subscriptions(store_id);
CREATE INDEX IF NOT EXISTS idx_store_plan_subscriptions_status ON store_plan_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_store_plan_subscriptions_next_billing ON store_plan_subscriptions(next_billing_date);

CREATE OR REPLACE FUNCTION update_store_plan_subscriptions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_store_plan_subscriptions_updated_at
  BEFORE UPDATE ON store_plan_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION update_store_plan_subscriptions_updated_at();

-- ============================================================================
-- 5. 반려동물 (pets)
-- ============================================================================
CREATE TABLE IF NOT EXISTS pets (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
    -- dog, cat, other
  breed TEXT NOT NULL,
  gender TEXT NOT NULL,
    -- male, female, unknown
  age TEXT NOT NULL,
  personality TEXT,
  images TEXT[],
  videos TEXT[],
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pets_store_id ON pets(store_id);
CREATE INDEX IF NOT EXISTS idx_pets_created_at ON pets(created_at);

-- ============================================================================
-- 6. 캠페인 (campaigns)
-- ============================================================================
CREATE TABLE IF NOT EXISTS campaigns (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  pet_id BIGINT REFERENCES pets(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  hashtags TEXT[],
  images TEXT[],
  videos TEXT[],
  channels TEXT[] NOT NULL,
    -- instagram, facebook, tiktok, youtube, kakao, naver
  status TEXT NOT NULL DEFAULT 'DRAFT',
    -- DRAFT, SUBMITTED, PENDING_REVIEW, APPROVED, REJECTED_BY_POLICY, RUNNING, PAUSED, PAUSED_BY_BILLING, STOPPED
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  CONSTRAINT campaigns_status_check CHECK (status IN (
    'DRAFT',
    'SUBMITTED',
    'PENDING_REVIEW',
    'APPROVED',
    'REJECTED_BY_POLICY',
    'RUNNING',
    'PAUSED',
    'PAUSED_BY_BILLING',
    'STOPPED'
  ))
);

CREATE INDEX IF NOT EXISTS idx_campaigns_store_id ON campaigns(store_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_pet_id ON campaigns(pet_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(status);
CREATE INDEX IF NOT EXISTS idx_campaigns_created_at ON campaigns(created_at);

-- ============================================================================
-- 7. 크리에이티브 (creatives)
-- ============================================================================
CREATE TABLE IF NOT EXISTS creatives (
  id BIGSERIAL PRIMARY KEY,
  campaign_id BIGINT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  channel TEXT NOT NULL,
    -- instagram, facebook, tiktok, youtube, kakao, naver
  content JSONB NOT NULL,
    -- 채널별 최적화된 콘텐츠
  status TEXT NOT NULL DEFAULT 'DRAFT',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_creatives_campaign_id ON creatives(campaign_id);
CREATE INDEX IF NOT EXISTS idx_creatives_channel ON creatives(channel);

-- ============================================================================
-- 8. 정책 위반 기록 (policy_violations)
-- ============================================================================
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

-- ============================================================================
-- 주석
-- ============================================================================
COMMENT ON TABLE stores IS '매장 정보';
COMMENT ON COLUMN stores.is_complete IS '필수 필드 완성 여부: name, short_description, images(≥1)';

COMMENT ON TABLE store_plan_subscriptions IS '매장 요금제 구독 정보 (월 결제 상태 관리)';
COMMENT ON COLUMN store_plan_subscriptions.status IS '구독 상태: ACTIVE, OVERDUE, CANCELLED';

COMMENT ON TABLE campaigns IS '캠페인 (광고)';
COMMENT ON COLUMN campaigns.status IS '캠페인 상태: DRAFT, SUBMITTED, PENDING_REVIEW, APPROVED, REJECTED_BY_POLICY, RUNNING, PAUSED, PAUSED_BY_BILLING, STOPPED';

COMMENT ON TABLE policy_violations IS '정책 위반 기록 (캠페인 상태 전이 근거)';
COMMENT ON COLUMN policy_violations.type IS '위반 유형: KEYWORD, AI_POLICY';

