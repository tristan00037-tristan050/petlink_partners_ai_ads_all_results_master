-- P0: store_plan_subscriptions 테이블 생성
-- 월 결제 상태 기반 제어를 위한 구독 정보

CREATE TABLE IF NOT EXISTS store_plan_subscriptions (
  id BIGSERIAL PRIMARY KEY,
  store_id BIGINT NOT NULL REFERENCES stores(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES plans(id),
  status TEXT NOT NULL DEFAULT 'ACTIVE',
    -- ACTIVE: 정상
    -- OVERDUE: 미납
    -- CANCELLED: 취소
  cycle_start DATE NOT NULL,
  cycle_end DATE NOT NULL,
  next_billing_date DATE NOT NULL,
  last_paid_at TIMESTAMPTZ,
  grace_period_days INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(store_id)
);

CREATE INDEX IF NOT EXISTS idx_store_plan_subscriptions_store_id ON store_plan_subscriptions(store_id);
CREATE INDEX IF NOT EXISTS idx_store_plan_subscriptions_status ON store_plan_subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_store_plan_subscriptions_next_billing ON store_plan_subscriptions(next_billing_date);

-- updated_at 자동 갱신 트리거
CREATE OR REPLACE FUNCTION update_store_plan_subscriptions_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_store_plan_subscriptions_updated_at
  BEFORE UPDATE ON store_plan_subscriptions
  FOR EACH ROW
  EXECUTE FUNCTION update_store_plan_subscriptions_updated_at();

COMMENT ON TABLE store_plan_subscriptions IS '매장 요금제 구독 정보 (월 결제 상태 관리)';
COMMENT ON COLUMN store_plan_subscriptions.status IS '구독 상태: ACTIVE, OVERDUE, CANCELLED';
COMMENT ON COLUMN store_plan_subscriptions.grace_period_days IS '미납 유예 기간 (일)';

