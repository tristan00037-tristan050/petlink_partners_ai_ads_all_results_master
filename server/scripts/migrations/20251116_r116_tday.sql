-- 최종 증빙 번들 메타(불변 해시 + 매니페스트)
CREATE TABLE IF NOT EXISTS golive_evidence(
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  sha256 TEXT NOT NULL,
  manifest JSONB NOT NULL,
  created_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- T‑Day 오케스트레이션 감사 로그
CREATE TABLE IF NOT EXISTS golive_audit(
  id BIGSERIAL PRIMARY KEY,
  kind TEXT NOT NULL,          -- prep | launch | rollback | evidence
  actor TEXT,
  payload JSONB,
  ok BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT now()
);

