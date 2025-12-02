-- r5: Domain Core DDL 수정 (stores 테이블에 name, address, phone 추가)

-- stores 테이블에 name, address, phone 컬럼 추가 (없는 경우만)
DO $$ 
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='name') THEN
    ALTER TABLE stores ADD COLUMN name TEXT;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='address') THEN
    ALTER TABLE stores ADD COLUMN address TEXT;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='phone') THEN
    ALTER TABLE stores ADD COLUMN phone TEXT;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='stores' AND column_name='status') THEN
    ALTER TABLE stores ADD COLUMN status TEXT DEFAULT 'active';
    ALTER TABLE stores ALTER COLUMN status SET NOT NULL;
  END IF;
END $$;

