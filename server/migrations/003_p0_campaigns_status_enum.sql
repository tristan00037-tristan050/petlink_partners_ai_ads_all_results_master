-- P0: campaigns 테이블 상태 열거 확장
-- REJECTED_BY_POLICY, PENDING_REVIEW, PAUSED_BY_BILLING 추가

-- 기존 campaigns 테이블이 있다면 ALTER, 없으면 CREATE
DO $$
BEGIN
  -- campaigns 테이블이 없으면 생성
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaigns') THEN
    CREATE TABLE campaigns (
      id BIGSERIAL PRIMARY KEY,
      store_id BIGINT NOT NULL,
      pet_id BIGINT,
      title TEXT NOT NULL,
      body TEXT NOT NULL,
      hashtags TEXT[],
      images TEXT[],
      videos TEXT[],
      channels TEXT[],
      status TEXT NOT NULL DEFAULT 'DRAFT',
      created_at TIMESTAMPTZ DEFAULT now(),
      updated_at TIMESTAMPTZ DEFAULT now()
    );
  END IF;

  -- status 컬럼에 새로운 상태값 허용 (CHECK 제약조건이 있다면 제거 후 재생성)
  -- PostgreSQL에서는 ENUM 대신 TEXT + CHECK 제약조건 사용 권장
  -- 기존 CHECK 제약조건 확인 및 업데이트
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints 
    WHERE table_name = 'campaigns' AND constraint_name LIKE '%status%'
  ) THEN
    -- 기존 제약조건 제거 (이름 확인 필요)
    ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_status_check;
  END IF;

  -- 새로운 상태값 포함한 CHECK 제약조건 추가
  ALTER TABLE campaigns ADD CONSTRAINT campaigns_status_check 
    CHECK (status IN (
      'DRAFT',
      'SUBMITTED',
      'PENDING_REVIEW',
      'APPROVED',
      'REJECTED_BY_POLICY',
      'RUNNING',
      'PAUSED',
      'PAUSED_BY_BILLING',
      'STOPPED'
    ));
END $$;

-- 인덱스 추가 (검색 성능)
CREATE INDEX IF NOT EXISTS idx_campaigns_store_id ON campaigns(store_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_status ON campaigns(status);
CREATE INDEX IF NOT EXISTS idx_campaigns_created_at ON campaigns(created_at);

COMMENT ON COLUMN campaigns.status IS '캠페인 상태: DRAFT, SUBMITTED, PENDING_REVIEW, APPROVED, REJECTED_BY_POLICY, RUNNING, PAUSED, PAUSED_BY_BILLING, STOPPED';

