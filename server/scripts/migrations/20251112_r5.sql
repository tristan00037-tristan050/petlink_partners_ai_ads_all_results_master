-- P2-r5 마이그레이션: Housekeeping, DLQ (스키마 변경 없음, 라우트만 추가)
-- r5는 주로 운영 기능(housekeeping, DLQ 조회)이므로 별도 스키마 변경 없음
-- idempotency_keys와 outbox 테이블은 r4에서 이미 생성됨

-- 필요시 인덱스 추가 (성능 최적화)
CREATE INDEX IF NOT EXISTS idx_idempotency_keys_expire_at_cleanup ON idempotency_keys(expire_at) WHERE expire_at < NOW();
CREATE INDEX IF NOT EXISTS idx_outbox_failed_dlq ON outbox(status, attempts, created_at) WHERE status = 'FAILED' AND attempts >= 3;


