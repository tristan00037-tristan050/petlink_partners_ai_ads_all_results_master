CREATE TABLE IF NOT EXISTS ledger_periods(
  period TEXT PRIMARY KEY,           -- 'YYYY-MM'
  status TEXT NOT NULL DEFAULT 'OPEN', -- OPEN|CLOSED
  totals JSONB DEFAULT '{}'::jsonb,
  closed_by TEXT,
  closed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS ledger_period_snapshots(
  id BIGSERIAL PRIMARY KEY,
  period TEXT NOT NULL REFERENCES ledger_periods(period) ON DELETE CASCADE,
  advertiser_id BIGINT NOT NULL,
  charges INTEGER NOT NULL,  -- +금액 합 (live_ledger.amount > 0)
  refunds INTEGER NOT NULL,  -- 환불 절대값 합 (live_ledger.amount < 0 인 항목의 |amount|)
  net INTEGER NOT NULL,      -- 합계(부호 포함): charges - refunds
  entries INTEGER NOT NULL,  -- 트랜잭션 수
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ledg_snap_period_adv ON ledger_period_snapshots(period, advertiser_id);

