-- r11.8 chargeback_cases 보강: assignee/priority/due_at
ALTER TABLE IF EXISTS chargeback_cases
  ADD COLUMN IF NOT EXISTS assignee TEXT,
  ADD COLUMN IF NOT EXISTS priority TEXT DEFAULT 'P3',
  ADD COLUMN IF NOT EXISTS due_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_cbk_cases_due_at ON chargeback_cases(due_at);

-- 티켓 디스패치 로그(외부 시스템 연계 기록)
CREATE TABLE IF NOT EXISTS cbk_ticket_log(
  id BIGSERIAL PRIMARY KEY,
  case_id BIGINT NOT NULL,
  kind TEXT DEFAULT 'WEBHOOK',
  target_url TEXT,
  payload JSONB,
  response JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

