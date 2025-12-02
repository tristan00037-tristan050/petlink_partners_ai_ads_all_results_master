CREATE TABLE IF NOT EXISTS payout_batches(
  id BIGSERIAL PRIMARY KEY,
  period TEXT NOT NULL,                  -- 'YYYY-MM'
  status TEXT NOT NULL DEFAULT 'draft',  -- draft|approved|sent|settled|failed
  total_amount BIGINT NOT NULL DEFAULT 0,
  item_count INTEGER NOT NULL DEFAULT 0,
  dryrun BOOLEAN NOT NULL DEFAULT TRUE,
  created_by TEXT,
  approved_by TEXT,
  approved_at TIMESTAMPTZ,
  note TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS payout_batch_items(
  id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES payout_batches(id) ON DELETE CASCADE,
  advertiser_id BIGINT NOT NULL,
  amount BIGINT NOT NULL,
  payee_name TEXT,
  bank_code TEXT,
  account_no TEXT,
  meta JSONB DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS payout_webhook_log(
  id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES payout_batches(id) ON DELETE CASCADE,
  sent_at TIMESTAMPTZ DEFAULT now(),
  status TEXT,
  response JSONB
);

