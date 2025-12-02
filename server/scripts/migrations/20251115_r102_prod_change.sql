CREATE TABLE IF NOT EXISTS prod_change_requests(
  id BIGSERIAL PRIMARY KEY,
  kind TEXT NOT NULL,                 -- 예: 'go-live-payments'
  payload JSONB NOT NULL,             -- 제안 구성 (예: {"billing_mode":"live"})
  status TEXT NOT NULL DEFAULT 'PENDING',  -- PENDING|APPROVED|APPLIED|REJECTED
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  approved_by TEXT,
  approved_at TIMESTAMPTZ,
  applied_by TEXT,
  applied_at TIMESTAMPTZ,
  notes TEXT
);

CREATE TABLE IF NOT EXISTS prod_change_events(
  id BIGSERIAL PRIMARY KEY,
  req_id BIGINT NOT NULL REFERENCES prod_change_requests(id) ON DELETE CASCADE,
  actor TEXT,
  action TEXT,                        -- CREATED|APPROVED|APPLY_DRYRUN|APPLIED|REJECTED|NOTE
  data JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

