-- 정산 태깅: txid → tags
CREATE TABLE IF NOT EXISTS ledger_tx_tags(
  txid TEXT PRIMARY KEY,
  tags TEXT[] NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 기간별 차지백 영향(분리 보관)
CREATE TABLE IF NOT EXISTS ledger_period_cbk_impact(
  period TEXT NOT NULL,               -- 'YYYY-MM'
  advertiser_id BIGINT NOT NULL,
  cbk_amount INTEGER NOT NULL DEFAULT 0,  -- 합계(대부분 음수)
  cases INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY(period, advertiser_id)
);

-- 차지백 SLA 인시던트(증빙 미첨부 지연 등)
CREATE TABLE IF NOT EXISTS cbk_incidents(
  id BIGSERIAL PRIMARY KEY,
  case_id BIGINT NOT NULL REFERENCES chargeback_cases(id) ON DELETE CASCADE,
  kind TEXT NOT NULL DEFAULT 'SLA_MISS_EVIDENCE',
  opened_at TIMESTAMPTZ DEFAULT now(),
  acked BOOLEAN DEFAULT FALSE,
  acked_by TEXT,
  acked_at TIMESTAMPTZ,
  note TEXT
);
CREATE INDEX IF NOT EXISTS idx_cbk_incidents_open ON cbk_incidents(acked, opened_at DESC);

