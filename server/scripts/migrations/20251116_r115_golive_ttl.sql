CREATE TABLE IF NOT EXISTS pilot_retention_policy(
  table_name TEXT PRIMARY KEY,
  ttl_days   INTEGER NOT NULL
);
INSERT INTO pilot_retention_policy(table_name, ttl_days) VALUES
  -- 레저/증빙
  ('live_ledger',             1825),  -- 5y
  ('ci_evidence',             2555),  -- 7y
  -- 지급/영수증/전송/디스패치
  ('payout_batches',          1095),  -- 3y
  ('payout_batch_items',      1095),
  ('payout_bank_files',       1095),
  ('payout_transfers',        1825),
  ('payout_dispatch_log',      365),
  ('payout_webhook_log',       180),
  ('payout_ack_events',        365),
  ('payout_settlements',      1825),
  -- 환불/리컨
  ('refund_requests',         1095),
  ('refund_incidents',        1095),
  ('recon_jobs',               365),
  ('recon_diffs',              365),
  -- 램핑/운영
  ('subs_autoroute_journal',    90),
  ('subs_ramp_incidents',      365)
ON CONFLICT (table_name) DO UPDATE SET ttl_days=EXCLUDED.ttl_days;

