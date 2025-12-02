-- 1) 일일 라이브 한도/횟수 제한(간단 설정)
CREATE TABLE IF NOT EXISTS live_billing_limits(
  id BOOL PRIMARY KEY DEFAULT TRUE,
  max_amount_per_tx INTEGER NOT NULL DEFAULT 50000,          -- 1회 한도(원)
  max_amount_per_day INTEGER NOT NULL DEFAULT 200000,         -- 일일 총액
  max_attempts_per_day INTEGER NOT NULL DEFAULT 10,           -- 일일 횟수
  dryrun BOOLEAN NOT NULL DEFAULT TRUE                        -- 기본 드라이런
);
INSERT INTO live_billing_limits(id) VALUES(TRUE) ON CONFLICT(id) DO NOTHING;

-- 2) 라이브 결제 저널(시뮬 포함)
CREATE TABLE IF NOT EXISTS live_billing_journal(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id BIGINT,
  amount INTEGER,
  mode TEXT,                 -- dryrun|live
  eligible_live BOOLEAN,
  decided_mode TEXT,         -- live|sbx
  result TEXT,               -- SIM_OK|SIM_FAIL|LIVE_OK|LIVE_FAIL
  message TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

