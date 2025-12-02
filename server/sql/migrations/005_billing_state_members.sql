-- r6: Billing, Campaign State Machine, Store Members

-- Invoices / Items
CREATE TABLE IF NOT EXISTS invoices (
  id SERIAL PRIMARY KEY,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  subscription_id INTEGER REFERENCES store_plan_subscriptions(id) ON DELETE SET NULL,
  period_start TIMESTAMPTZ NOT NULL,
  period_end   TIMESTAMPTZ NOT NULL,
  due_date     TIMESTAMPTZ NOT NULL,
  amount_krw   INTEGER NOT NULL DEFAULT 0,
  status       TEXT NOT NULL DEFAULT 'pending',  -- pending|paid|overdue|canceled
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  paid_at      TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_invoices_store ON invoices(store_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON invoices(status);

CREATE TABLE IF NOT EXISTS invoice_items (
  id SERIAL PRIMARY KEY,
  invoice_id INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  amount_krw  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON invoice_items(invoice_id);

-- Campaign State History
CREATE TABLE IF NOT EXISTS campaign_status_history (
  id SERIAL PRIMARY KEY,
  campaign_id INTEGER NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  from_status TEXT,
  to_status   TEXT NOT NULL,
  reason_code TEXT,  -- blocked_by_policy / blocked_by_billing / manual / etc
  note        TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_csh_campaign ON campaign_status_history(campaign_id);

-- Store Members
CREATE TABLE IF NOT EXISTS store_members (
  id SERIAL PRIMARY KEY,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  user_id  INTEGER NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
  role     TEXT NOT NULL DEFAULT 'owner',  -- owner|manager|staff
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (store_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_members_store ON store_members(store_id);

