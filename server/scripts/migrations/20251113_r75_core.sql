-- 광고주 프로필
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='advertiser_profile') THEN
    CREATE TABLE advertiser_profile(
      advertiser_id INTEGER PRIMARY KEY,
      name TEXT,
      phone TEXT,
      email TEXT,
      address TEXT,
      meta JSONB DEFAULT '{}'::jsonb,
      updated_at timestamptz NOT NULL DEFAULT now()
    );
  END IF;
END$$;

-- 월 구독 결제
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ad_subscriptions') THEN
    CREATE TABLE ad_subscriptions(
      id BIGSERIAL PRIMARY KEY,
      advertiser_id INTEGER NOT NULL,
      plan_code TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK (amount>=0),
      currency TEXT NOT NULL DEFAULT 'KRW',
      method_id BIGINT,
      bill_day INTEGER NOT NULL CHECK (bill_day BETWEEN 1 AND 31),
      status TEXT NOT NULL CHECK (status IN ('ACTIVE','PAUSED','CANCELED')),
      retry_count INTEGER NOT NULL DEFAULT 0,
      last_attempt_at timestamptz,
      next_attempt_at timestamptz,
      next_charge_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE INDEX IF NOT EXISTS idx_subs_adv ON ad_subscriptions(advertiser_id);
    CREATE INDEX IF NOT EXISTS idx_subs_sched ON ad_subscriptions(next_attempt_at, next_charge_at);
  ELSE
    BEGIN
      ALTER TABLE ad_subscriptions ADD COLUMN IF NOT EXISTS retry_count INTEGER NOT NULL DEFAULT 0;
      ALTER TABLE ad_subscriptions ADD COLUMN IF NOT EXISTS last_attempt_at timestamptz;
      ALTER TABLE ad_subscriptions ADD COLUMN IF NOT EXISTS next_attempt_at timestamptz;
      ALTER TABLE ad_subscriptions ADD COLUMN IF NOT EXISTS next_charge_at timestamptz;
    EXCEPTION WHEN duplicate_column THEN END;
    CREATE INDEX IF NOT EXISTS idx_subs_sched ON ad_subscriptions(next_attempt_at, next_charge_at);
  END IF;
END$$;

-- 간단 영수증 번호
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='ad_invoices' AND column_name='receipt_no') THEN
    ALTER TABLE ad_invoices ADD COLUMN receipt_no TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ux_ad_invoices_receipt_no') THEN
    CREATE UNIQUE INDEX ux_ad_invoices_receipt_no ON ad_invoices(receipt_no) WHERE receipt_no IS NOT NULL;
  END IF;
END$$;
