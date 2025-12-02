-- 광고주 프로필
CREATE TABLE IF NOT EXISTS advertiser_profile(
  advertiser_id INTEGER PRIMARY KEY,
  name          TEXT,
  biz_no        TEXT,
  phone         TEXT,
  address       TEXT,
  logo_url      TEXT,
  site_url      TEXT,
  tags          TEXT[],
  meta          JSONB DEFAULT '{}',
  updated_at    timestamptz DEFAULT now(),
  created_at    timestamptz DEFAULT now()
);

-- 채널 규칙(기본값 삽입)
CREATE TABLE IF NOT EXISTS channel_rules(
  channel TEXT PRIMARY KEY,               -- 'NAVER','INSTAGRAM' 등
  max_len_headline INTEGER,
  max_len_body     INTEGER,
  max_hashtags     INTEGER,
  allow_links      BOOLEAN,
  meta             JSONB DEFAULT '{}',
  updated_at       timestamptz DEFAULT now(),
  created_at       timestamptz DEFAULT now()
);

INSERT INTO channel_rules(channel,max_len_headline,max_len_body,max_hashtags,allow_links)
  VALUES
    ('NAVER', 30, 140, 10, true),
    ('INSTAGRAM', 60, 2200, 30, true)
ON CONFLICT (channel) DO NOTHING;

-- 보조 인덱스
CREATE INDEX IF NOT EXISTS idx_adv_profile_updated_at ON advertiser_profile(updated_at);
