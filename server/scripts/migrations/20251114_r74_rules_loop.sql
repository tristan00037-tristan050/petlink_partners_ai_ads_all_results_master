-- 0-1) channel_rules(버전관리) 추가
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='channel_rules') THEN
    CREATE TABLE channel_rules(
      id BIGSERIAL PRIMARY KEY,
      channel TEXT NOT NULL,
      rule_version INTEGER NOT NULL,
      status TEXT NOT NULL CHECK (status IN ('DRAFT','ACTIVE','DEPRECATED')),
      config JSONB NOT NULL,
      effective_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ DEFAULT now()
    );
    CREATE INDEX idx_channel_rules_ch ON channel_rules(channel);
    CREATE UNIQUE INDEX uq_channel_rules_active ON channel_rules(channel) WHERE status='ACTIVE';
  ELSE
    -- 기존 테이블에 컬럼 추가
    BEGIN
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS id BIGSERIAL;
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS rule_version INTEGER DEFAULT 1;
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'ACTIVE';
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS config JSONB DEFAULT '{}'::jsonb;
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS effective_at TIMESTAMPTZ;
      ALTER TABLE channel_rules ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT now();
    EXCEPTION WHEN duplicate_column THEN NULL;
    END;
  END IF;
END$$;
CREATE INDEX IF NOT EXISTS idx_channel_rules_ch ON channel_rules(channel);

-- ad_channel_rules 가 이미 존재한다면 ACTIVE 스냅샷을 채워 넣음(1회성)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ad_channel_rules') THEN
    INSERT INTO channel_rules(channel, rule_version, status, config, effective_at)
    SELECT acr.channel, 1, 'ACTIVE', acr.config, now()
    FROM ad_channel_rules acr
    ON CONFLICT DO NOTHING;
  END IF;
END$$;

-- 0-2) ad_moderation_logs 테이블 생성(없으면) + loop_id 추가
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='ad_moderation_logs') THEN
    CREATE TABLE ad_moderation_logs(
      id BIGSERIAL PRIMARY KEY,
      advertiser_id INTEGER,
      channel TEXT,
      decision TEXT,
      used_autofix BOOLEAN DEFAULT false,
      loop_id TEXT,
      dur_ms INTEGER,
      created_at TIMESTAMPTZ DEFAULT now()
    );
    CREATE INDEX idx_ad_mod_loop ON ad_moderation_logs(loop_id);
  ELSE
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='ad_moderation_logs' AND column_name='loop_id') THEN
      ALTER TABLE ad_moderation_logs ADD COLUMN loop_id TEXT;
      CREATE INDEX IF NOT EXISTS idx_ad_mod_loop ON ad_moderation_logs(loop_id);
    END IF;
  END IF;
END$$;
