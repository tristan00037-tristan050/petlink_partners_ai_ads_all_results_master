CREATE TABLE IF NOT EXISTS advertiser_profile (
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER NOT NULL UNIQUE,
  store_name TEXT,
  business_number TEXT,
  address TEXT,
  phone TEXT,
  email TEXT,
  website TEXT,
  description TEXT,
  logo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_advertiser_profile_adv_id ON advertiser_profile(advertiser_id);
