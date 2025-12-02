ALTER TABLE idempotency_keys ALTER COLUMN expire_at SET DEFAULT (now() + interval '14 days');
UPDATE idempotency_keys SET expire_at = now() + interval '14 days' WHERE expire_at IS NULL;

