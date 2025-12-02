CREATE TABLE IF NOT EXISTS credit_memos(
  id BIGSERIAL PRIMARY KEY,
  memo_no TEXT UNIQUE NOT NULL,
  advertiser_id INTEGER NOT NULL,
  amount INTEGER NOT NULL,
  reason TEXT,
  status TEXT NOT NULL CHECK(status IN('PENDING','APPLIED','CANCELED')),
  applied_at timestamptz,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_credit_memos_adv ON credit_memos(advertiser_id);

CREATE TABLE IF NOT EXISTS ad_settlements(
  id BIGSERIAL PRIMARY KEY,
  payment_id BIGINT REFERENCES ad_payments(id),
  invoice_no TEXT NOT NULL,
  gross INTEGER NOT NULL,
  fee INTEGER NOT NULL,
  net INTEGER NOT NULL,
  settled_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ad_settlements_invoice ON ad_settlements(invoice_no);
