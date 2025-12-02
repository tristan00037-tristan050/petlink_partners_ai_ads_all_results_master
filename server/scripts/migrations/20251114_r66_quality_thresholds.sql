CREATE TABLE IF NOT EXISTS quality_thresholds(
  channel TEXT PRIMARY KEY,
  min_approval NUMERIC NOT NULL,
  max_rejection NUMERIC NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
