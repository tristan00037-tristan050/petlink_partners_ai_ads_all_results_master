CREATE INDEX IF NOT EXISTS idx_ad_payments_created_at ON ad_payments(created_at);
CREATE INDEX IF NOT EXISTS idx_ad_invoices_created_at ON ad_invoices(created_at);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='outbox_dlq')
     AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='dlq') THEN
    CREATE VIEW outbox_dlq AS
      SELECT id, topic, payload, reason, failed_at AS created_at FROM dlq;
  END IF;
END$$;
