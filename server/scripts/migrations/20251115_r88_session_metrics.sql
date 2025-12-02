-- 세션 이벤트(웹앱/어드민 공통)
CREATE TABLE IF NOT EXISTS session_events(
  id BIGSERIAL PRIMARY KEY,
  surface TEXT CHECK (surface IN ('app','admin')) NOT NULL,
  kind TEXT NOT NULL,               -- refresh_ok|refresh_fail|idle_logout|forced_logout|login|logout|tab_sync
  ms INTEGER,                       -- 소요시간(ms) (refresh_ok 등)
  code TEXT,                        -- 에러코드/부가코드
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_session_events_created ON session_events(created_at);
CREATE INDEX IF NOT EXISTS idx_session_events_surface_kind ON session_events(surface,kind);

-- OIDC(SSO) 지표
CREATE TABLE IF NOT EXISTS oidc_events(
  id BIGSERIAL PRIMARY KEY,
  surface TEXT CHECK (surface IN ('app','admin')) NOT NULL,
  event TEXT NOT NULL,              -- login_start|login_ok|login_error|refresh_ok|refresh_error
  code TEXT,                        -- 상태코드/오류코드
  latency_ms INTEGER,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_oidc_events_created ON oidc_events(created_at);
CREATE INDEX IF NOT EXISTS idx_oidc_events_surface_event ON oidc_events(surface,event);
