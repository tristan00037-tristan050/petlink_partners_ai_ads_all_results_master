-- subscription_live_policy 테이블이 없으면 생성
CREATE TABLE IF NOT EXISTS subscription_live_policy(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id BIGINT UNIQUE NOT NULL,
  enabled BOOLEAN DEFAULT TRUE,
  percent_live INTEGER DEFAULT 0,
  cap_amount_per_day INTEGER,
  cap_attempts_per_day INTEGER,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 램핑 컬럼 추가
ALTER TABLE subscription_live_policy
  ADD COLUMN IF NOT EXISTS ramp_enabled BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS ramp_plan TEXT DEFAULT '0,5,10,25,50',
  ADD COLUMN IF NOT EXISTS ramp_index INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ramp_min_interval_minutes INTEGER DEFAULT 1440,
  ADD COLUMN IF NOT EXISTS ramp_last_at TIMESTAMPTZ;

