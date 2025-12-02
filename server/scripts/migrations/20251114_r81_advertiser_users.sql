-- advertiser_users 테이블 생성
CREATE TABLE IF NOT EXISTS advertiser_users(
  id BIGSERIAL PRIMARY KEY,
  advertiser_id INTEGER NOT NULL,
  email TEXT NOT NULL UNIQUE,
  pw_salt TEXT NOT NULL,
  pw_hash TEXT NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_advertiser_users_email ON advertiser_users(email);
CREATE INDEX IF NOT EXISTS idx_advertiser_users_adv_id ON advertiser_users(advertiser_id);

