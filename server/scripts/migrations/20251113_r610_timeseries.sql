-- 24h/5m 버킷 집계에 사용할 뷰(존재 시 재생성 안함)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='v_payments_5m') THEN
    CREATE VIEW v_payments_5m AS
    SELECT
      to_timestamp(floor(extract(epoch FROM created_at)/300)*300) AT TIME ZONE 'UTC' AS ts5,
      SUM(CASE WHEN status='CAPTURED'   THEN 1 ELSE 0 END)::int AS captured,
      SUM(CASE WHEN status='AUTHORIZED' THEN 1 ELSE 0 END)::int AS authorized,
      SUM(CASE WHEN status='FAILED'     THEN 1 ELSE 0 END)::int AS failed,
      COUNT(*)::int AS total
    FROM ad_payments
    GROUP BY 1;

    -- outbox_dlq 뷰가 없으면 생성 (dlq 테이블 기반)
    IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='outbox_dlq') 
       AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='dlq') THEN
      CREATE VIEW outbox_dlq AS 
        SELECT id, topic, payload, reason, COALESCE(failed_at, now()) AS created_at FROM dlq;
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='v_outbox_dlq_5m') THEN
      CREATE VIEW v_outbox_dlq_5m AS
      SELECT
        to_timestamp(floor(extract(epoch FROM created_at)/300)*300) AT TIME ZONE 'UTC' AS ts5,
        COUNT(*)::int AS dlq
      FROM outbox_dlq
      GROUP BY 1;
    END IF;

    -- 선택 지표: PM 루프 계측(p95)
    CREATE VIEW v_ops_loop_5m AS
    SELECT
      to_timestamp(floor(extract(epoch FROM created_at)/300)*300) AT TIME ZONE 'UTC' AS ts5,
      percentile_disc(0.95) WITHIN GROUP (ORDER BY value)::int AS p95_ms
    FROM ad_ops_metrics
    WHERE metric='PM_LOOP_MS'
    GROUP BY 1;
  END IF;
END$$;
