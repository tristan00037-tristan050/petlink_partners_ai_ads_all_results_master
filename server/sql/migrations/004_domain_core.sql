-- r5: Domain Core DDL
-- STORES, SUBSCRIPTIONS, PETS, CAMPAIGNS, CREATIVES, POLICY_VIOLATIONS

-- STORES
CREATE TABLE IF NOT EXISTS stores (
  id SERIAL PRIMARY KEY,
  owner_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tenant TEXT NOT NULL,
  name TEXT NOT NULL,
  address TEXT,
  phone TEXT,
  status TEXT NOT NULL DEFAULT 'active', -- active|suspended|closed
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_stores_owner ON stores(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_stores_tenant ON stores(tenant);

-- SUBSCRIPTIONS (store ↔ plan)
CREATE TABLE IF NOT EXISTS store_plan_subscriptions (
  id SERIAL PRIMARY KEY,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  plan_code TEXT NOT NULL REFERENCES plans(code),
  status TEXT NOT NULL DEFAULT 'active', -- active|canceled|pending
  period_start TIMESTAMPTZ NOT NULL DEFAULT now(),
  period_end TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 day'),
  auto_renew BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_subs_store ON store_plan_subscriptions(store_id);
CREATE INDEX IF NOT EXISTS idx_subs_status ON store_plan_subscriptions(status);

-- PETS
CREATE TABLE IF NOT EXISTS pets (
  id SERIAL PRIMARY KEY,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  species TEXT NOT NULL,       -- dog|cat|other...
  breed TEXT,
  age_months INTEGER DEFAULT 0,
  sex TEXT,                    -- M|F|unknown
  status TEXT NOT NULL DEFAULT 'listed', -- listed|adopted|withdrawn
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pets_store ON pets(store_id);

-- CAMPAIGNS
CREATE TABLE IF NOT EXISTS campaigns (
  id SERIAL PRIMARY KEY,
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  objective TEXT NOT NULL,      -- traffic|leads
  daily_budget_krw INTEGER NOT NULL DEFAULT 0,
  start_date DATE,
  end_date DATE,
  status TEXT NOT NULL DEFAULT 'draft', -- draft|active|paused
  primary_text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_campaigns_store ON campaigns(store_id);

-- CREATIVES (간단 URL 보관)
CREATE TABLE IF NOT EXISTS creatives (
  id SERIAL PRIMARY KEY,
  campaign_id INTEGER NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  type TEXT NOT NULL,           -- image|video|text
  url TEXT,
  text TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_creatives_campaign ON creatives(campaign_id);

-- POLICY VIOLATIONS
CREATE TABLE IF NOT EXISTS policy_violations (
  id SERIAL PRIMARY KEY,
  entity_type TEXT NOT NULL,    -- 'campaign' 등
  entity_id INTEGER NOT NULL,
  field TEXT NOT NULL,          -- 'primary_text' 등
  rule TEXT NOT NULL,           -- 'banned_word'
  snippet TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_policy_entity ON policy_violations(entity_type, entity_id);

