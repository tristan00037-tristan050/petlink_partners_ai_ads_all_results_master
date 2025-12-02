CREATE TABLE IF NOT EXISTS ad_invoices(
  id BIGSERIAL PRIMARY KEY,
  invoice_no TEXT UNIQUE NOT NULL,
  advertiser_id INTEGER NOT NULL,
  amount INTEGER NOT NULL CHECK(amount>=0),
  currency TEXT NOT NULL DEFAULT 'KRW',
  status TEXT NOT NULL CHECK(status IN('DUE','PAID','CANCELED')),
  meta JSONB,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ad_invoices_adv ON ad_invoices(advertiser_id);

CREATE TABLE IF NOT EXISTS payment_methods(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER NOT NULL,
  pm_type TEXT NOT NULL CHECK(pm_type IN('CARD','NAVERPAY','KAKAOPAY','BANK')),
  provider TEXT NOT NULL,
  token TEXT NOT NULL,
  brand TEXT,
  last4 TEXT,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(advertiser_id, provider, token)
);
CREATE INDEX IF NOT EXISTS idx_pm_adv ON payment_methods(advertiser_id);
DO $$BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname='ux_pm_default_adv') THEN
    CREATE UNIQUE INDEX ux_pm_default_adv ON payment_methods(advertiser_id) WHERE is_default IS TRUE;
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS ad_payments(
  id BIGSERIAL PRIMARY KEY,
  invoice_no TEXT NOT NULL REFERENCES ad_invoices(invoice_no),
  advertiser_id INTEGER NOT NULL,
  method_id BIGINT REFERENCES payment_methods(id),
  amount INTEGER NOT NULL CHECK(amount>=0),
  currency TEXT NOT NULL DEFAULT 'KRW',
  provider TEXT NOT NULL DEFAULT 'bootpay',
  provider_txn_id TEXT,
  status TEXT NOT NULL CHECK(status IN('PENDING','AUTHORIZED','CAPTURED','CANCELED','FAILED')),
  metadata JSONB,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(provider, provider_txn_id)
);
CREATE INDEX IF NOT EXISTS idx_ad_payments_invoice ON ad_payments(invoice_no);
CREATE INDEX IF NOT EXISTS idx_ad_payments_status  ON ad_payments(status);

DO $$BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='ad_payments_guard_transition') THEN
    EXECUTE '
    CREATE FUNCTION ad_payments_guard_transition() RETURNS trigger AS $f$
    DECLARE old TEXT := COALESCE(OLD.status,''PENDING''); DECLARE nw TEXT := NEW.status;
    BEGIN
      IF old=nw THEN RETURN NEW; END IF;
      IF old=''PENDING''    AND nw IN(''AUTHORIZED'',''FAILED'') THEN RETURN NEW; END IF;
      IF old=''AUTHORIZED'' AND nw IN(''CAPTURED'',''CANCELED'',''FAILED'') THEN RETURN NEW; END IF;
      RAISE EXCEPTION ''invalid transition: % -> %'', old, nw;
    END; $f$ LANGUAGE plpgsql;
    ';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='ad_payments_guard_transition_tr') THEN
    CREATE TRIGGER ad_payments_guard_transition_tr
      BEFORE UPDATE ON ad_payments FOR EACH ROW
      EXECUTE PROCEDURE ad_payments_guard_transition();
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS ad_subscriptions(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER NOT NULL,
  plan_code TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK(amount>=0),
  currency TEXT NOT NULL DEFAULT 'KRW',
  method_id BIGINT REFERENCES payment_methods(id),
  status TEXT NOT NULL CHECK(status IN('ACTIVE','PAUSED','CANCELED')),
  next_charge_at timestamptz,
  created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bank_deposits(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER,
  invoice_no TEXT,
  amount INTEGER NOT NULL CHECK(amount>=0),
  deposit_time timestamptz NOT NULL,
  bank_code TEXT, account_mask TEXT,
  ref_no TEXT, memo TEXT, created_by TEXT,
  created_at timestamptz DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_bank_deposits_adv ON bank_deposits(advertiser_id);
