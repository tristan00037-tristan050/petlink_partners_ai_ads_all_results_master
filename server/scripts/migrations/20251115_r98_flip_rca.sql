-- pilot_flip_events 테이블 생성 (없으면)
CREATE TABLE IF NOT EXISTS pilot_flip_events(
  id BIGSERIAL PRIMARY KEY,
  prev_go BOOLEAN NOT NULL,
  next_go BOOLEAN NOT NULL,
  flipped_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  source TEXT,
  payload JSONB,
  acked BOOLEAN DEFAULT FALSE
);

-- pilot_flip_events 보강: ACK 메타/원인/서프레션
DO $body$BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='pilot_flip_events' AND column_name='ack_by') THEN
    ALTER TABLE pilot_flip_events ADD COLUMN ack_by TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='pilot_flip_events' AND column_name='ack_reason') THEN
    ALTER TABLE pilot_flip_events ADD COLUMN ack_reason TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='pilot_flip_events' AND column_name='ack_note') THEN
    ALTER TABLE pilot_flip_events ADD COLUMN ack_note TEXT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='pilot_flip_events' AND column_name='ack_at') THEN
    ALTER TABLE pilot_flip_events ADD COLUMN ack_at TIMESTAMPTZ;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='pilot_flip_events' AND column_name='suppressed') THEN
    ALTER TABLE pilot_flip_events ADD COLUMN suppressed BOOLEAN DEFAULT FALSE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='pilot_flip_events' AND column_name='cause_tags') THEN
    ALTER TABLE pilot_flip_events ADD COLUMN cause_tags TEXT[] DEFAULT ARRAY[]::TEXT[];
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='pilot_flip_events' AND column_name='cause_summary') THEN
    ALTER TABLE pilot_flip_events ADD COLUMN cause_summary TEXT;
  END IF;
END$body$;

-- 소거 룰
CREATE TABLE IF NOT EXISTS pilot_flip_rules(
  id BIGSERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  params JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO pilot_flip_rules(name,active,params)
VALUES
  ('suppress_same_cause_minutes', TRUE, '{"minutes":30}'),
  ('business_hours_only', TRUE, '{"tz":"Asia/Seoul","start":"09:00","end":"21:00"}')
ON CONFLICT (name) DO NOTHING;

