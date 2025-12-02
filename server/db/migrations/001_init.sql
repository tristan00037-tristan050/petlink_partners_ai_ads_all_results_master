-- P2-r3 영속화 스키마 초안 (PostgreSQL)
-- 주의: 운영 전환 시 인덱스 최적화 및 파티셔닝 고려 필요

-- 스토어 설정
CREATE TABLE stores (
    id BIGSERIAL PRIMARY KEY,
    tz TEXT NOT NULL DEFAULT 'Asia/Seoul',
    prefs JSONB NOT NULL DEFAULT '{"ig_enabled":true,"tt_enabled":true,"yt_enabled":false,"kakao_enabled":false,"naver_enabled":false}',
    radius_km INTEGER NOT NULL DEFAULT 6 CHECK (radius_km >= 1 AND radius_km <= 20),
    weights JSONB NOT NULL DEFAULT '{"mon":1,"tue":1,"wed":1,"thu":1.05,"fri":1.15,"sat":1.30,"sun":1.25,"holiday":1.30,"holidays":[]}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_stores_created_at ON stores(created_at);

-- 동물 정보
CREATE TABLE animals (
    id BIGSERIAL PRIMARY KEY,
    store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    species TEXT NOT NULL,
    breed TEXT NOT NULL,
    sex TEXT NOT NULL,
    age_label TEXT,
    title TEXT,
    caption TEXT,
    note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_animals_store_id ON animals(store_id);
CREATE INDEX idx_animals_created_at ON animals(created_at);

-- 초안
CREATE TABLE drafts (
    id BIGSERIAL PRIMARY KEY,
    store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    animal_id BIGINT REFERENCES animals(id) ON DELETE SET NULL,
    copy TEXT NOT NULL,
    channels TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    status TEXT NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'PUBLISHED', 'PARTIAL', 'APPROVED', 'FAILED')),
    history JSONB[] NOT NULL DEFAULT ARRAY[]::JSONB[],
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    published_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_drafts_store_id ON drafts(store_id);
CREATE INDEX idx_drafts_animal_id ON drafts(animal_id);
CREATE INDEX idx_drafts_status ON drafts(status);
CREATE INDEX idx_drafts_created_at ON drafts(created_at);

-- 일일 스케줄
CREATE TABLE schedules (
    store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    ym CHAR(7) NOT NULL,  -- YYYY-MM
    date DATE NOT NULL,
    amount INTEGER NOT NULL CHECK (amount >= 0),
    min INTEGER NOT NULL CHECK (min >= 0),
    max INTEGER NOT NULL CHECK (max >= 0),
    PRIMARY KEY (store_id, date)
);

CREATE INDEX idx_schedules_store_ym ON schedules(store_id, ym);
CREATE INDEX idx_schedules_date ON schedules(date);

-- 일일 지출 집계
CREATE TABLE spend_daily (
    store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    cost BIGINT NOT NULL DEFAULT 0 CHECK (cost >= 0),
    PRIMARY KEY (store_id, date)
);

CREATE INDEX idx_spend_daily_store_date ON spend_daily(store_id, date);
CREATE INDEX idx_spend_daily_date ON spend_daily(date);

-- 멱등성 보장
CREATE TABLE idempotency (
    scope TEXT NOT NULL,
    store_id BIGINT NOT NULL,
    key TEXT NOT NULL,
    status INTEGER NOT NULL,  -- HTTP status code
    response JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ttl_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (scope, store_id, key)
);

CREATE INDEX idx_idempotency_ttl ON idempotency(ttl_at);
-- TTL 정리: DELETE FROM idempotency WHERE ttl_at < NOW();

-- 승인 토큰 (단일 사용 보장)
CREATE TABLE approval_tokens (
    jti UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    draft_id BIGINT NOT NULL REFERENCES drafts(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    used_at TIMESTAMPTZ,
    exp_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT approval_tokens_single_use CHECK (used_at IS NULL OR used_at > issued_at)
);

CREATE INDEX idx_approval_tokens_draft_id ON approval_tokens(draft_id);
CREATE INDEX idx_approval_tokens_exp_at ON approval_tokens(exp_at);
CREATE INDEX idx_approval_tokens_unused ON approval_tokens(used_at) WHERE used_at IS NULL;

-- 감사 로그
CREATE TABLE audit (
    id BIGSERIAL PRIMARY KEY,
    store_id BIGINT REFERENCES stores(id) ON DELETE SET NULL,
    type TEXT NOT NULL,  -- 'api_call', 'draft_publish', 'pacer_apply', etc.
    payload JSONB NOT NULL,
    at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_store_id ON audit(store_id);
CREATE INDEX idx_audit_type ON audit(type);
CREATE INDEX idx_audit_at ON audit(at);

-- 메트릭 집계 (선택: 실시간 집계용)
CREATE TABLE metrics_daily (
    store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
    channel TEXT NOT NULL,
    date DATE NOT NULL,
    impressions BIGINT NOT NULL DEFAULT 0,
    views BIGINT NOT NULL DEFAULT 0,
    clicks BIGINT NOT NULL DEFAULT 0,
    cost BIGINT NOT NULL DEFAULT 0,
    conversions_dm INTEGER NOT NULL DEFAULT 0,
    conversions_call INTEGER NOT NULL DEFAULT 0,
    conversions_route INTEGER NOT NULL DEFAULT 0,
    conversions_lead INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (store_id, channel, date)
);

CREATE INDEX idx_metrics_daily_date ON metrics_daily(date);
CREATE INDEX idx_metrics_daily_channel ON metrics_daily(channel);

-- 트리거: updated_at 자동 갱신
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_stores_updated_at BEFORE UPDATE ON stores
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_animals_updated_at BEFORE UPDATE ON animals
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_drafts_updated_at BEFORE UPDATE ON drafts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


