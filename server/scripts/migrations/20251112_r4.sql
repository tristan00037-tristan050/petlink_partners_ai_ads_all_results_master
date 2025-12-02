-- P2-r4 마이그레이션: 멱등키, Outbox, 초안/승인토큰 DB 이관

-- 멱등키 테이블
CREATE TABLE IF NOT EXISTS idempotency_keys (
    key TEXT NOT NULL,
    method TEXT,
    path TEXT,
    req_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'IN_PROGRESS' CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'FAILED')),
    response JSONB,
    status_code INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    last_seen TIMESTAMPTZ,
    expire_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '14 days'),
    PRIMARY KEY (key)
);

CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expire_at ON idempotency_keys(expire_at);
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_status ON idempotency_keys(status);

-- Outbox 테이블
CREATE TABLE IF NOT EXISTS outbox (
    id BIGSERIAL PRIMARY KEY,
    aggregate_type TEXT NOT NULL,
    aggregate_id BIGINT NOT NULL,
    event_type TEXT NOT NULL,
    payload JSONB NOT NULL,
    headers JSONB,
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'SENT', 'FAILED')),
    attempts INTEGER NOT NULL DEFAULT 0,
    available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    processed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_outbox_unprocessed ON outbox(status, available_at) WHERE status = 'PENDING';
CREATE INDEX IF NOT EXISTS idx_outbox_created_at ON outbox(created_at);

-- 초안 테이블 확장 (승인토큰 필드 추가)
ALTER TABLE drafts ADD COLUMN IF NOT EXISTS approve_token TEXT;
ALTER TABLE drafts ADD COLUMN IF NOT EXISTS results JSONB;

-- 승인 토큰 테이블 (이미 있으면 스킵)
CREATE TABLE IF NOT EXISTS approval_tokens (
    jti UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id BIGINT NOT NULL REFERENCES drafts(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    used_at TIMESTAMPTZ,
    exp_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT approval_tokens_single_use CHECK (used_at IS NULL OR used_at > issued_at)
);

CREATE INDEX IF NOT EXISTS idx_approval_tokens_draft_id ON approval_tokens(draft_id);
CREATE INDEX IF NOT EXISTS idx_approval_tokens_exp_at ON approval_tokens(exp_at);
CREATE INDEX IF NOT EXISTS idx_approval_tokens_unused ON approval_tokens(used_at) WHERE used_at IS NULL;

-- TTL 정리 함수 (선택)
CREATE OR REPLACE FUNCTION cleanup_expired_idempotency_keys()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM idempotency_keys WHERE expire_at < NOW();
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

