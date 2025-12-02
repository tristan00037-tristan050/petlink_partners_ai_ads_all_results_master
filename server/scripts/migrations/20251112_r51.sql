-- r5.1 기본 스키마: payments 테이블 생성
CREATE TABLE IF NOT EXISTS payments (
    id BIGSERIAL PRIMARY KEY,
    order_id TEXT NOT NULL UNIQUE,
    store_id BIGINT,
    amount INTEGER NOT NULL,
    currency TEXT NOT NULL DEFAULT 'KRW',
    provider TEXT NOT NULL DEFAULT 'bootpay',
    provider_txn_id TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'AUTHORIZED', 'CAPTURED', 'CANCELED', 'FAILED')),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_store_id ON payments(store_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments(status);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments(created_at);

-- outbox_dlq 테이블 (outbox.js에서 사용)
CREATE TABLE IF NOT EXISTS outbox_dlq (
    id BIGSERIAL PRIMARY KEY,
    src_outbox_id BIGINT,
    aggregate_type TEXT NOT NULL,
    aggregate_id BIGINT NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    headers JSONB,
    failure TEXT,
    failed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_outbox_dlq_src_outbox_id ON outbox_dlq(src_outbox_id);


