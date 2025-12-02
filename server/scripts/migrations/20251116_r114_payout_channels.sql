-- 송신 채널 구성(HTTPS/SFTP/모의)
CREATE TABLE IF NOT EXISTS payout_channels(
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  kind TEXT NOT NULL DEFAULT 'MOCK', -- MOCK|HTTPS|SFTP
  endpoint_url TEXT,                 -- HTTPS 용
  headers JSONB,                     -- HTTPS 헤더
  sftp_host TEXT, sftp_path TEXT,    -- SFTP 용(모의)
  enabled BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 은행파일(배치 단위). r11.3에 없을 수 있으므로 생성.
CREATE TABLE IF NOT EXISTS payout_bank_files(
  id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES payout_batches(id) ON DELETE CASCADE,
  format TEXT NOT NULL DEFAULT 'CSV',
  content TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  idempotency_key TEXT,                         -- (채널별 중복방지 키)
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 전송 엔트리(배치 항목 → 전송 상태)
CREATE TABLE IF NOT EXISTS payout_transfers(
  id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES payout_batches(id) ON DELETE CASCADE,
  advertiser_id BIGINT,
  amount INTEGER,
  currency TEXT DEFAULT 'KRW',
  status TEXT NOT NULL DEFAULT 'PENDING',       -- PENDING|SENT|CONFIRMED|FAILED
  bank_file_id BIGINT REFERENCES payout_bank_files(id) ON DELETE SET NULL,
  error TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 채널 디스패치 로그(중복방지)
CREATE TABLE IF NOT EXISTS payout_dispatch_log(
  id BIGSERIAL PRIMARY KEY,
  batch_id BIGINT NOT NULL REFERENCES payout_batches(id) ON DELETE CASCADE,
  bank_file_id BIGINT REFERENCES payout_bank_files(id) ON DELETE SET NULL,
  channel_id BIGINT REFERENCES payout_channels(id) ON DELETE SET NULL,
  idempotency_key TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL,                          -- SENT|ALREADY_SENT|ERROR|DRYRUN|RECEIPT
  response_code INTEGER,
  response_body TEXT,
  sent_at TIMESTAMPTZ DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_dispatch_dedupe ON payout_dispatch_log(channel_id, idempotency_key);

