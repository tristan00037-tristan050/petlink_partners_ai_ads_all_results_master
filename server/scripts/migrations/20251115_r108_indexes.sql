-- r10.5 저널 인덱스(일일 리포트용)
CREATE INDEX IF NOT EXISTS idx_subs_journal_day ON subs_autoroute_journal((created_at::date));
CREATE INDEX IF NOT EXISTS idx_subs_journal_outcome ON subs_autoroute_journal(outcome);
-- r10.7 백오프 이벤트 인덱스
CREATE INDEX IF NOT EXISTS idx_ramp_backoff_day ON ramp_backoff_events((created_at::date));
CREATE INDEX IF NOT EXISTS idx_ramp_backoff_tags ON ramp_backoff_events USING GIN (reason_tags);

