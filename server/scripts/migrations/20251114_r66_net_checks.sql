CREATE TABLE IF NOT EXISTS billing_net_checks(
  id BIGSERIAL PRIMARY KEY,
  ok BOOLEAN NOT NULL,
  latency_ms INTEGER,
  detail TEXT,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_billing_net_checks_created_at ON billing_net_checks(created_at);
