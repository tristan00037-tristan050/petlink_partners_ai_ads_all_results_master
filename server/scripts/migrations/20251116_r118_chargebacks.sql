CREATE TABLE IF NOT EXISTS chargeback_cases(
  id BIGSERIAL PRIMARY KEY,
  txid TEXT,
  advertiser_id BIGINT,
  amount INTEGER NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'KRW',
  status TEXT NOT NULL DEFAULT 'OPEN',         -- OPEN|REPRESENTED|CLOSED
  outcome TEXT,                                 -- WIN|LOSE|WRITE_OFF|CANCELED
  reason_code TEXT,
  opened_at TIMESTAMPTZ DEFAULT now(),
  represented_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  sla_due_at TIMESTAMPTZ,
  created_by TEXT,
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chargeback_evidence(
  id BIGSERIAL PRIMARY KEY,
  case_id BIGINT NOT NULL REFERENCES chargeback_cases(id) ON DELETE CASCADE,
  filename TEXT,
  sha256 TEXT,
  kind TEXT,          -- receipt|screenshot|email|terms|log|other
  bytes INTEGER,
  note TEXT,
  content BYTEA,      -- 경량 파일 보관(소용량 기준)
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chargeback_events(
  id BIGSERIAL PRIMARY KEY,
  case_id BIGINT NOT NULL REFERENCES chargeback_cases(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,           -- OPEN|EVIDENCE|REPRESENT|CLOSE|NOTE
  payload JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 회계 영향은 별도 조정 테이블에 기록(필요 시 집계에 union 가능)
CREATE TABLE IF NOT EXISTS cbk_adjustments(
  id BIGSERIAL PRIMARY KEY,
  case_id BIGINT NOT NULL REFERENCES chargeback_cases(id) ON DELETE CASCADE,
  advertiser_id BIGINT,
  amount INTEGER NOT NULL,      -- LOSE/WRITE_OFF 시 음수
  currency TEXT NOT NULL DEFAULT 'KRW',
  note TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

