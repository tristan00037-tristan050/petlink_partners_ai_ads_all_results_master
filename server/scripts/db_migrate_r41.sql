-- r4.1: users 테이블 확장 (tenant, role 추가)
-- 기존 users 테이블이 있다면 컬럼 추가, 없으면 생성

-- tenant, role 컬럼 추가 (없는 경우만)
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='tenant') THEN
    ALTER TABLE users ADD COLUMN tenant VARCHAR(50) DEFAULT 'default';
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='role') THEN
    ALTER TABLE users ADD COLUMN role VARCHAR(20) DEFAULT 'user';
  END IF;
END $$;

-- 인덱스 추가
CREATE INDEX IF NOT EXISTS idx_users_tenant ON users(tenant);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

