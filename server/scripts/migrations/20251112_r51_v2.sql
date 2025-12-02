-- 상태 전이 가드 트리거
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='payments_guard_transition') THEN
    CREATE OR REPLACE FUNCTION payments_guard_transition() RETURNS trigger AS $f$
    DECLARE old TEXT := COALESCE(OLD.status,'PENDING');
    DECLARE nw  TEXT := NEW.status;
    BEGIN
      IF old = nw THEN RETURN NEW; END IF;
      IF old = 'PENDING'    AND nw IN ('AUTHORIZED','FAILED') THEN RETURN NEW; END IF;
      IF old = 'AUTHORIZED' AND nw IN ('CAPTURED','CANCELED','FAILED') THEN RETURN NEW; END IF;
      IF old = 'CAPTURED'   AND nw IN ('CANCELED','FAILED') THEN RETURN NEW; END IF;
      IF old IN ('CANCELED','FAILED') THEN
        RAISE EXCEPTION 'invalid transition: % -> %', old, nw;
      END IF;
      RAISE EXCEPTION 'invalid transition: % -> %', old, nw;
    END;
    $f$ LANGUAGE plpgsql;
  END IF;
END$$;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='payments_guard_transition_tr') THEN
    CREATE TRIGGER payments_guard_transition_tr
    BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE PROCEDURE payments_guard_transition();
  END IF;
END$$;

-- 기존 provider_txn_id UNIQUE 제약이 있다면 제거(컬럼 단일 유니크 → 부분 유니크로 전환)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='payments'::regclass AND conname='payments_provider_txn_id_key'
  ) THEN
    ALTER TABLE payments DROP CONSTRAINT payments_provider_txn_id_key;
  END IF;
END$$;

-- provider + provider_txn_id 부분 유니크(널 허용)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname='ux_payments_provider_txn_nullable'
  ) THEN
    CREATE UNIQUE INDEX ux_payments_provider_txn_nullable
      ON payments(provider, provider_txn_id)
      WHERE provider_txn_id IS NOT NULL;
  END IF;
END$$;

-- 금액 음수 방지
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
      WHERE conrelid='payments'::regclass AND conname='payments_amount_nonneg'
  ) THEN
    ALTER TABLE payments
      ADD CONSTRAINT payments_amount_nonneg CHECK (amount >= 0);
  END IF;
END$$;
