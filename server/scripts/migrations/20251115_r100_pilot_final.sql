CREATE TABLE IF NOT EXISTS pilot_final_reports(
  id BIGSERIAL PRIMARY KEY,
  period_start TIMESTAMPTZ NOT NULL,
  period_end   TIMESTAMPTZ NOT NULL,
  title        TEXT NOT NULL,
  summary_md   TEXT NOT NULL,
  payload      JSONB NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pilot_final_reports_period ON pilot_final_reports(period_start, period_end);

