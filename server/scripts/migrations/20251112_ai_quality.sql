DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ad_creatives') THEN
    CREATE TABLE ad_creatives(
      id BIGSERIAL PRIMARY KEY,
      advertiser_id INTEGER,
      channel TEXT,                              -- META/YOUTUBE/KAKAO/NAVER
      flags JSONB DEFAULT '{}'::jsonb,           -- {"forbidden_count":int,"reject_reasons":[...]}
      format_ok BOOLEAN DEFAULT TRUE,
      created_at TIMESTAMPTZ DEFAULT now(),
      reviewed_at TIMESTAMPTZ,
      approved_at TIMESTAMPTZ
    );
    CREATE INDEX IF NOT EXISTS idx_ad_creatives_ch ON ad_creatives(channel);
    CREATE INDEX IF NOT EXISTS idx_ad_creatives_cre ON ad_creatives(created_at);
  ELSE
    BEGIN
      ALTER TABLE ad_creatives ADD COLUMN IF NOT EXISTS channel TEXT;
      ALTER TABLE ad_creatives ADD COLUMN IF NOT EXISTS format_ok BOOLEAN DEFAULT TRUE;
      ALTER TABLE ad_creatives ADD COLUMN IF NOT EXISTS flags JSONB DEFAULT '{}'::jsonb;
    EXCEPTION WHEN duplicate_column THEN
      -- no-op
    END;
    CREATE INDEX IF NOT EXISTS idx_ad_creatives_ch ON ad_creatives(channel);
    CREATE INDEX IF NOT EXISTS idx_ad_creatives_cre ON ad_creatives(created_at);
  END IF;
END$$;
