-- P0 Core DDL - PostgreSQL
-- 날짜: 2025-11-17
-- 범위: users, stores, plans, store_plan_subscriptions

-- ============================================================================
-- 1. 사용자 (users)
-- ============================================================================
CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  name VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- ============================================================================
-- 2. 매장 (stores)
-- ============================================================================
CREATE TABLE IF NOT EXISTS stores (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  address TEXT,
  phone VARCHAR(20),
  business_hours TEXT,
  short_description TEXT NOT NULL,
  description TEXT,
  images TEXT[],
  is_complete BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stores_user_id ON stores(user_id);
CREATE INDEX IF NOT EXISTS idx_stores_is_complete ON stores(is_complete);

-- updated_at 자동 갱신
CREATE OR REPLACE FUNCTION update_stores_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_stores_updated_at
  BEFORE UPDATE ON stores
  FOR EACH ROW
  EXECUTE FUNCTION update_stores_updated_at();

-- ============================================================================
-- 3. 요금제 (plans)
-- ============================================================================
CREATE TABLE IF NOT EXISTS plans (
  id BIGSERIAL PRIMARY KEY,
  code VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(100) NOT NULL,
  price INTEGER NOT NULL,
  ad_budget INTEGER NOT NULL,
  features TEXT[],
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================================
-- 4. 매장 요금제 구독 (store_plan_subscriptions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS store_plan_subscriptions (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES plans(id),
  status TEXT NOT NULL DEFAULT 'ACTIVE',
  cycle_start DATE NOT NULL,
  cycle_end DATE NOT NULL,
  next_billing_date DATE NOT NULL,
  last_paid_at TIMESTAMPTZ,
  grace_period_days INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(store_id)
);

CREATE INDEX IF NOT EXISTS idx_store_plan_subscriptions_store_id ON store_plan_subscriptions(store_id);
CREATE INDEX IF NOT EXISTS idx_store_plan_subscriptions_status ON store_plan_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_store_plan_subscriptions_next_billing ON store_plan_subscriptions(next_billing_date);

CREATE OR REPLACE FUNCTION update_store_plan_subscriptions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_store_plan_subscriptions_updated_at
  BEFORE UPDATE ON store_plan_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION update_store_plan_subscriptions_updated_at();

