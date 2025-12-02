CREATE TABLE IF NOT EXISTS quality_thresholds(
  id BIGSERIAL PRIMARY KEY,
  channel TEXT NOT NULL,                -- META / YOUTUBE / KAKAO / NAVER
  min_approval NUMERIC NOT NULL,        -- 승인율 임계(0.0~1.0)
  max_rejection NUMERIC NOT NULL,       -- 거절율 임계(0.0~1.0)
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(channel)
);
