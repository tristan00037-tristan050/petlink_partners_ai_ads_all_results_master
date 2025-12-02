CREATE TABLE IF NOT EXISTS payment_methods(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER NOT NULL,
  pm_type TEXT NOT NULL CHECK(pm_type IN ('CARD','NAVERPAY','KAKAOPAY','BANK')),
  provider TEXT NOT NULL,
  token TEXT NOT NULL,
  brand TEXT,
  last4 TEXT,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  UNIQUE(advertiser_id, provider, token)
);
CREATE INDEX IF NOT EXISTS idx_pm_adv ON payment_methods(advertiser_id);

ALTER TABLE ad_payments ADD COLUMN IF NOT EXISTS method_id BIGINT;

DO $$
DECLARE has_fk BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t  ON t.oid=c.conrelid
    JOIN pg_class rt ON rt.oid=c.confrelid
    WHERE t.relname='ad_payments' AND c.contype='f' AND rt.relname='payment_methods'
  ) INTO has_fk;
  IF NOT has_fk THEN
    BEGIN
      ALTER TABLE ad_payments
        ADD CONSTRAINT ad_payments_method_id_fkey
        FOREIGN KEY (method_id) REFERENCES payment_methods(id);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
  END IF;
END$$;
