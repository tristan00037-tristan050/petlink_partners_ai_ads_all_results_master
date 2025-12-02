-- r7: Notification Queue
CREATE TABLE IF NOT EXISTS notification_queue (
  id SERIAL PRIMARY KEY,
  type TEXT NOT NULL,           -- billing_due_d2 | billing_due_d1 | billing_due | billing_overdue_d1
  store_id INTEGER NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  campaign_id INTEGER REFERENCES campaigns(id) ON DELETE SET NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  scheduled_at TIMESTAMPTZ NOT NULL,
  sent_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pending',  -- pending|sent|failed
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_notif_sched ON notification_queue (scheduled_at, status);
CREATE INDEX IF NOT EXISTS idx_notif_store ON notification_queue (store_id);

