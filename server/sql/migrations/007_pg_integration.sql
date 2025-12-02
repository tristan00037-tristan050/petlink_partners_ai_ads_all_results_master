-- r8: PG(Webhook) 연동 및 Ops 하드닝

-- 결제 엔터티
CREATE TABLE IF NOT EXISTS payments (
  id SERIAL PRIMARY KEY,
  provider TEXT NOT NULL,                         -- 'stripe'|'toss'|'iamport'|'mock'
  provider_payment_id TEXT,                       -- PG 고유 결제ID
  invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  amount_krw INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',         -- pending|succeeded|failed|refunded
  method TEXT,                                    -- card|vbank|...
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_pay_provider_pid
  ON payments(provider, provider_payment_id) WHERE provider_payment_id IS NOT NULL;

-- PG 이벤트 로그(멱등성)
CREATE TABLE IF NOT EXISTS payment_events (
  id SERIAL PRIMARY KEY,
  provider TEXT NOT NULL,
  event_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payment_id INTEGER REFERENCES payments(id) ON DELETE SET NULL,
  invoice_id INTEGER REFERENCES invoices(id) ON DELETE SET NULL,
  payload JSONB NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_payment_event_provider_eid
  ON payment_events(provider, event_id);

-- 웹훅 원본 로그
CREATE TABLE IF NOT EXISTS webhook_logs (
  id SERIAL PRIMARY KEY,
  provider TEXT NOT NULL,
  event_id TEXT,
  signature_valid BOOLEAN,
  http_status INTEGER,
  payload JSONB,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 알림 큐 멱등성(중복 방지)
DO $$ BEGIN
  ALTER TABLE notification_queue
    ADD CONSTRAINT ux_notif_unique UNIQUE (type, store_id, scheduled_at);
EXCEPTION
  WHEN duplicate_table THEN RAISE NOTICE 'constraint already exists';
  WHEN duplicate_object THEN RAISE NOTICE 'constraint already exists';
END $$;

-- 정책 해제 감사필드
DO $$ BEGIN
  ALTER TABLE policy_violations ADD COLUMN resolved_by TEXT;
EXCEPTION
  WHEN duplicate_column THEN RAISE NOTICE 'resolved_by already exists';
END $$;
DO $$ BEGIN
  ALTER TABLE policy_violations ADD COLUMN resolved_note TEXT;
EXCEPTION
  WHEN duplicate_column THEN RAISE NOTICE 'resolved_note already exists';
END $$;

