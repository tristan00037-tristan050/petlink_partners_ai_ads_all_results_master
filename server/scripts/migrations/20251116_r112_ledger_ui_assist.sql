-- live_ledger에 조회용 컬럼 보강(없을 때만)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='live_ledger') THEN
    ALTER TABLE live_ledger ADD COLUMN IF NOT EXISTS txid TEXT;
    ALTER TABLE live_ledger ADD COLUMN IF NOT EXISTS advertiser_id BIGINT;
    ALTER TABLE live_ledger ADD COLUMN IF NOT EXISTS kind TEXT;
    ALTER TABLE live_ledger ADD COLUMN IF NOT EXISTS status TEXT;
    ALTER TABLE live_ledger ADD COLUMN IF NOT EXISTS amount INTEGER;
    ALTER TABLE live_ledger ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
  END IF;
END$$;

-- recon_diffs에 조회/해소 컬럼 보강(없을 때만)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='recon_diffs') THEN
    ALTER TABLE recon_diffs ADD COLUMN IF NOT EXISTS txid TEXT;
    ALTER TABLE recon_diffs ADD COLUMN IF NOT EXISTS amount INTEGER;
    ALTER TABLE recon_diffs ADD COLUMN IF NOT EXISTS side TEXT;
    ALTER TABLE recon_diffs ADD COLUMN IF NOT EXISTS code TEXT;
    ALTER TABLE recon_diffs ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'OPEN';
    ALTER TABLE recon_diffs ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
    ALTER TABLE recon_diffs ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ;
  END IF;
END$$;

-- refund_requests에 타임라인 컬럼 보강(없을 때만)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='refund_requests') THEN
    ALTER TABLE refund_requests ADD COLUMN IF NOT EXISTS requested_at TIMESTAMPTZ DEFAULT now();
    ALTER TABLE refund_requests ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
    ALTER TABLE refund_requests ADD COLUMN IF NOT EXISTS executed_at TIMESTAMPTZ;
  END IF;
END$$;

-- CI 증빙 테이블 존재 전제(r11.0). 없으면 경량 생성
CREATE TABLE IF NOT EXISTS ci_evidence(
  id BIGSERIAL PRIMARY KEY,
  ledger_txid TEXT,
  txid TEXT,
  kind TEXT,
  bundle_path TEXT,
  sha256 TEXT,
  meta JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Refund SLA 인시던트/티켓
CREATE TABLE IF NOT EXISTS refund_incidents(
  id BIGSERIAL PRIMARY KEY,
  refund_id BIGINT,
  severity TEXT NOT NULL DEFAULT 'warn',
  opened_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  acked BOOLEAN DEFAULT FALSE,
  acked_by TEXT,
  acked_at TIMESTAMPTZ,
  closed BOOLEAN DEFAULT FALSE,
  closed_at TIMESTAMPTZ,
  note TEXT
);

CREATE INDEX IF NOT EXISTS idx_refund_incidents_open ON refund_incidents(acked,closed,opened_at DESC);
