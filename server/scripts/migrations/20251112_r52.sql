ALTER TABLE payments ADD COLUMN IF NOT EXISTS refunded_total INTEGER NOT NULL DEFAULT 0;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS settled_at timestamptz;

CREATE TABLE IF NOT EXISTS refunds (
  id BIGSERIAL PRIMARY KEY,
  refund_id TEXT UNIQUE,
  order_id TEXT NOT NULL REFERENCES payments(order_id) ON DELETE CASCADE,
  amount INTEGER NOT NULL CHECK (amount > 0),
  reason TEXT,
  status TEXT NOT NULL CHECK (status IN ('REQUESTED','SUCCEEDED','FAILED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_refunds_order_id ON refunds(order_id);

CREATE TABLE IF NOT EXISTS settlements (
  id BIGSERIAL PRIMARY KEY,
  payment_id BIGINT REFERENCES payments(id) ON DELETE CASCADE,
  order_id TEXT NOT NULL,
  gross INTEGER NOT NULL,
  fee INTEGER NOT NULL,
  net INTEGER NOT NULL,
  settled_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_settlements_order_id ON settlements(order_id);
