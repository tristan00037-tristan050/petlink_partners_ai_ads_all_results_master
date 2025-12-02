CREATE INDEX IF NOT EXISTS idx_ad_payments_status  ON ad_payments(status);
CREATE INDEX IF NOT EXISTS idx_ad_payments_invoice ON ad_payments(invoice_no);
CREATE INDEX IF NOT EXISTS idx_pm_adv_default      ON payment_methods(advertiser_id, is_default);
CREATE INDEX IF NOT EXISTS idx_outbox_created_at   ON outbox(created_at);
DO $$BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='idempotency_keys' AND column_name='expires_at') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_idem_expires ON idempotency_keys(expires_at)';
  ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='idempotency_keys' AND column_name='exp_at') THEN
    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_idem_expires ON idempotency_keys(exp_at)';
  END IF;
END$$;
