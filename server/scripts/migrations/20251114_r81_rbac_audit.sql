-- 앱 역할
CREATE TABLE IF NOT EXISTS app_roles(
  code TEXT PRIMARY KEY,              -- OWNER, MANAGER, ANALYST
  created_at timestamptz DEFAULT now()
);
INSERT INTO app_roles(code) VALUES ('OWNER'),('MANAGER'),('ANALYST')
  ON CONFLICT (code) DO NOTHING;

-- 사용자-역할 매핑
CREATE TABLE IF NOT EXISTS app_user_roles(
  user_id BIGINT NOT NULL,
  role_code TEXT NOT NULL REFERENCES app_roles(code),
  created_at timestamptz DEFAULT now(),
  UNIQUE(user_id, role_code)
);

-- 세션/리프레시 토큰(존재 시 보강)
CREATE TABLE IF NOT EXISTS advertiser_sessions(
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL,
  refresh_token TEXT UNIQUE NOT NULL,
  expires_at timestamptz NOT NULL,
  rotated_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- 감사 로그
CREATE TABLE IF NOT EXISTS audit_logs(
  id BIGSERIAL PRIMARY KEY,
  ts timestamptz NOT NULL DEFAULT now(),
  actor_type TEXT NOT NULL CHECK (actor_type IN ('app','admin','system')),
  actor_id BIGINT,
  advertiser_id INTEGER,
  method TEXT, path TEXT, status INTEGER,
  req_id TEXT, ip TEXT,
  meta JSONB
);
CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit_logs(ts);
CREATE INDEX IF NOT EXISTS idx_audit_actor ON audit_logs(actor_type, actor_id);
