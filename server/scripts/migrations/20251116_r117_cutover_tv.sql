-- 컷오버/백아웃 액션 감사 로그
CREATE TABLE IF NOT EXISTS cutover_actions(
  id BIGSERIAL PRIMARY KEY,
  kind TEXT NOT NULL,                      -- CUTOVER | BACKOUT | RESUME | AUTO_BACKOUT
  advertiser_id BIGINT,
  before_percent INTEGER,
  after_percent  INTEGER,
  reason TEXT,
  actor  TEXT,
  source TEXT DEFAULT 'manual',            -- manual | guard | scheduler
  created_at TIMESTAMPTZ DEFAULT now()
);

-- TV 대시보드 상태(선택 캐시) - 없으면 사용하지 않음
CREATE TABLE IF NOT EXISTS tv_dash_cache(
  k TEXT PRIMARY KEY,
  v JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

