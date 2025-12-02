-- 라이브 레저(정산 원장)
CREATE TABLE IF NOT EXISTS live_ledger(
  id BIGSERIAL PRIMARY KEY,
  txid TEXT UNIQUE,                 -- 내부 트랜잭션 ID(없으면 생성)
  advertiser_id BIGINT,
  env TEXT DEFAULT 'sbx',           -- sbx|live
  kind TEXT NOT NULL,               -- CAPTURE|REFUND|ADJUST
  parent_txid TEXT,                 -- REFUND 대상 CAPTURE txid
  amount INTEGER NOT NULL,          -- +CAPTURE / -REFUND
  currency TEXT DEFAULT 'KRW',
  status TEXT DEFAULT 'SETTLED',    -- SETTLED|PENDING|FAILED
  external_id TEXT,                 -- PG 식별자(옵션)
  meta JSONB DEFAULT '{}'::jsonb,
  event_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_live_ledger_event ON live_ledger(event_at);
CREATE INDEX IF NOT EXISTS idx_live_ledger_adv   ON live_ledger(advertiser_id);

-- 환불 요청/흐름
CREATE TABLE IF NOT EXISTS refund_requests(
  id BIGSERIAL PRIMARY KEY,
  ledger_txid TEXT,                 -- 대상 CAPTURE txid
  advertiser_id BIGINT,
  amount INTEGER NOT NULL,
  reason TEXT,
  status TEXT DEFAULT 'REQUESTED',  -- REQUESTED|APPROVED|EXECUTED|FAILED|REJECTED
  actor TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ
);

-- 대사(리컨) 잡/차이
CREATE TABLE IF NOT EXISTS recon_jobs(
  id BIGSERIAL PRIMARY KEY,
  started_at TIMESTAMPTZ DEFAULT now(),
  ended_at TIMESTAMPTZ,
  status TEXT DEFAULT 'RUNNING',    -- RUNNING|OK|DIFF|ERROR
  note TEXT
);
CREATE TABLE IF NOT EXISTS recon_diffs(
  id BIGSERIAL PRIMARY KEY,
  job_id BIGINT REFERENCES recon_jobs(id) ON DELETE CASCADE,
  side TEXT,                        -- PAYMENTS|LIVE_JOURNAL|LEDGER
  ref_id TEXT,
  amount INTEGER,
  info JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- CI 증빙(경량) 메타
CREATE TABLE IF NOT EXISTS ci_evidence(
  id BIGSERIAL PRIMARY KEY,
  ledger_txid TEXT,
  kind TEXT,                        -- CAPTURE|REFUND
  bundle_path TEXT,
  sha256 TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

