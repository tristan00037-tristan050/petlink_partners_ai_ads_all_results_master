-- r5: Domain Core DDL 수정
-- 기존 stores 테이블에 컬럼 추가

-- stores 테이블에 owner_user_id, tenant 컬럼 추가 (없는 경우만)
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='owner_user_id') THEN
    ALTER TABLE stores ADD COLUMN owner_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE;
    -- 기존 데이터가 있다면 user_id를 owner_user_id로 복사
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='user_id') THEN
      UPDATE stores SET owner_user_id = user_id WHERE owner_user_id IS NULL;
    END IF;
    ALTER TABLE stores ALTER COLUMN owner_user_id SET NOT NULL;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='tenant') THEN
    ALTER TABLE stores ADD COLUMN tenant TEXT DEFAULT 'default';
    ALTER TABLE stores ALTER COLUMN tenant SET NOT NULL;
  END IF;
END $$;

-- 인덱스 추가 (없는 경우만)
CREATE INDEX IF NOT EXISTS idx_stores_owner ON stores(owner_user_id);
CREATE INDEX IF NOT EXISTS idx_stores_tenant ON stores(tenant);

-- 나머지 테이블들은 이미 생성되었으므로 스킵

