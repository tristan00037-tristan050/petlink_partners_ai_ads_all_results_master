-- payment_methods 보장(멱등)
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

-- ad_payments.method_id 컬럼 보강(멱등)
ALTER TABLE ad_payments ADD COLUMN IF NOT EXISTS method_id BIGINT;

-- 외래키 존재 여부를 시스템 카탈로그로 확인 후, 없으면 추가
DO $$
DECLARE
  has_fk BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class      t ON t.oid=c.conrelid
    JOIN pg_attribute  a ON a.attrelid=t.oid AND a.attnum = ANY (c.conkey)
    JOIN pg_class      rt ON rt.oid=c.confrelid
    WHERE t.relname='ad_payments'
      AND a.attname='method_id'
      AND c.contype='f'
      AND rt.relname='payment_methods'
  ) INTO has_fk;

  IF NOT has_fk THEN
    BEGIN
      ALTER TABLE ad_payments
        ADD CONSTRAINT ad_payments_method_id_fkey
        FOREIGN KEY (method_id) REFERENCES payment_methods(id);
    EXCEPTION WHEN duplicate_object THEN
      -- 동시 실행/이질 명칭 FK가 이미 있으면 무시
      NULL;
    END;
  END IF;
END$$;
