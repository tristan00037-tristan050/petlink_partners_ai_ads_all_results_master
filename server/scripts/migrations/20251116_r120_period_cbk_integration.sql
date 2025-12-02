-- 마감 스냅샷 보강(광고주별)
ALTER TABLE IF EXISTS ledger_period_snapshots
  ADD COLUMN IF NOT EXISTS cbk_win_amount        INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cbk_lose_amount       INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cbk_write_off_amount  INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS cbk_net_impact        INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS extras JSONB;

-- CBK 영향 테이블 보조 인덱스(있으면 멱등)
CREATE INDEX IF NOT EXISTS idx_cbk_impact_period_adv
  ON ledger_period_cbk_impact(period, advertiser_id);

