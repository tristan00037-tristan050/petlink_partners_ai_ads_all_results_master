-- admin_audit 테이블 생성(없으면)
CREATE TABLE IF NOT EXISTS admin_audit(
  id BIGSERIAL PRIMARY KEY,
  actor TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  action TEXT NOT NULL,
  diff JSONB,
  created_at timestamptz DEFAULT now()
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_admin_audit_entity ON admin_audit(entity, entity_id);
CREATE INDEX IF NOT EXISTS idx_admin_audit_created ON admin_audit(created_at);

-- advertiser_profile에 updated_at(없으면) 추가(관측성)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='advertiser_profile' AND column_name='updated_at') THEN
    ALTER TABLE advertiser_profile ADD COLUMN updated_at timestamptz DEFAULT now();
  END IF;
END $$;

-- updated_at 자동 갱신 트리거(멱등)
DO $func$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname='adv_profile_touch') THEN
    CREATE FUNCTION adv_profile_touch() RETURNS trigger AS $body$
    BEGIN 
      NEW.updated_at = now(); 
      RETURN NEW; 
    END $body$ LANGUAGE plpgsql;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='adv_profile_touch_tr') THEN
    CREATE TRIGGER adv_profile_touch_tr BEFORE UPDATE ON advertiser_profile
    FOR EACH ROW EXECUTE FUNCTION adv_profile_touch();
  END IF;
END $func$;
