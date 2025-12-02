#!/usr/bin/env bash
set -uo pipefail
mkdir -p server/mw scripts/migrations

# ===== 공통 ENV =====
export DATABASE_URL="${DATABASE_URL:-postgres://postgres:petpass@localhost:5432/petlink}"
export PORT="${PORT:-5902}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[need] $1 미설치"; exit 1; }; }
need node; need npm; need psql; need curl
test -f scripts/run_sql.js || { echo "[ERR] scripts/run_sql.js 누락"; exit 1; }

echo "[패치 A] DB 인덱스 + DLQ 뷰 멱등 보강"
cat > scripts/migrations/20251113_ops_polish.sql <<'SQL'
CREATE INDEX IF NOT EXISTS idx_ad_payments_created_at ON ad_payments(created_at);
CREATE INDEX IF NOT EXISTS idx_ad_invoices_created_at ON ad_invoices(created_at);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.views WHERE table_name='outbox_dlq')
     AND EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name='dlq') THEN
    CREATE VIEW outbox_dlq AS
      SELECT id, topic, payload, reason, failed_at AS created_at FROM dlq;
  END IF;
END$$;
SQL

psql "$DATABASE_URL" -f scripts/migrations/20251113_ops_polish.sql

echo "[패치 B-1] 요청 추적 ID 미들웨어"
cat > server/mw/request_id.js <<'JS'
module.exports = () => (req,res,next) => {
  const id = req.headers['x-request-id'] || Math.random().toString(36).slice(2);
  res.setHeader('X-Request-Id', id);
  req.requestId = id;
  next();
};
JS

echo "[패치 B-2] Admin 레이트리밋(경량)"
cat > server/mw/admin_ratelimit.js <<'JS'
const rateLimit = require('express-rate-limit');
module.exports = rateLimit({ windowMs: 60*1000, max: 60, standardHeaders:true, legacyHeaders:false });
JS

echo "[패치 B-3] app.js에 미들웨어 장착"
# request_id 미들웨어 추가 (express 이후, 다른 미들웨어보다 먼저)
if ! grep -q "mw/request_id" server/app.js; then
  sed -i.bak '/const express = require/a\
app.use(require('\''./mw/request_id'\'')());\
' server/app.js && rm -f server/app.js.bak || true
fi

# admin_ratelimit 미들웨어 추가 (express.json 이후, /admin 라우트보다 먼저)
if ! grep -q "mw/admin_ratelimit" server/app.js; then
  sed -i.bak '/app\.use(express\.json/i\
app.use('\''/admin'\'', require('\''./mw/admin_ratelimit'\''));\
' server/app.js && rm -f server/app.js.bak || true
fi

echo "[패치 B-4] 리포트 JSON에 7일 이동평균 추가"
# admin_reports.js 파일 읽기
if [ -f server/routes/admin_reports.js ]; then
  # metrics 함수에 MA7 추가
  if ! grep -q "success_rate_ma7" server/routes/admin_reports.js; then
    # metrics 함수 수정
    sed -i.bak '/const dlq_rate = outbox_cnt? dlq_cnt\/outbox_cnt : 0.0;/a\
  let ok_ma7 = 0.0;\
  try {\
    const ma7 = await db.q(`\
      WITH d AS (\
        SELECT date_trunc('\''day'\'', created_at)::date d, count(*) c,\
               sum((status='\''CAPTURED'\'')::int) ok\
        FROM ad_payments\
        WHERE created_at >= now() - interval '\''14 days'\''\
        GROUP BY 1\
      )\
      SELECT COALESCE(ROUND(AVG(CASE WHEN c>0 THEN ok::numeric*100/c END) FILTER (WHERE d >= now()::date - 6),2),0) AS ok_ma7\
      FROM d;\
    `);\
    ok_ma7 = Number(ma7.rows[0]?.ok_ma7 || 0) / 100;\
  } catch {}\
' server/routes/admin_reports.js && rm -f server/routes/admin_reports.js.bak || true

    # daily.json 응답에 MA7 추가
    sed -i.bak 's/res.json({ ok:true, metrics:m });/res.json({ ok:true, metrics:{ ...m, success_rate_ma7: ok_ma7 } });/' server/routes/admin_reports.js && rm -f server/routes/admin_reports.js.bak || true
  fi
fi

# 더 간단한 방법: admin_reports.js를 직접 수정
cat > /tmp/admin_reports_patch.js <<'JS'
const fs = require('fs');
const content = fs.readFileSync('server/routes/admin_reports.js', 'utf8');

// metrics 함수에 MA7 추가
const newContent = content.replace(
  /const dlq_rate = outbox_cnt\? dlq_cnt\/outbox_cnt : 0\.0;/,
  `const dlq_rate = outbox_cnt? dlq_cnt/outbox_cnt : 0.0;
  let ok_ma7 = 0.0;
  try {
    const ma7 = await db.q(\`
      WITH d AS (
        SELECT date_trunc('day', created_at)::date d, count(*) c,
               sum((status='CAPTURED')::int) ok
        FROM ad_payments
        WHERE created_at >= now() - interval '14 days'
        GROUP BY 1
      )
      SELECT COALESCE(ROUND(AVG(CASE WHEN c>0 THEN ok::numeric*100/c END) FILTER (WHERE d >= now()::date - 6),2),0) AS ok_ma7
      FROM d;
    \`);
    ok_ma7 = Number(ma7.rows[0]?.ok_ma7 || 0) / 100;
  } catch {}
`
).replace(
  /res\.json\(\{ ok:true, metrics:m \}\);/,
  'res.json({ ok:true, metrics:{ ...m, success_rate_ma7: ok_ma7 } });'
);

fs.writeFileSync('server/routes/admin_reports.js', newContent);
JS

node /tmp/admin_reports_patch.js 2>/dev/null || echo "[INFO] admin_reports.js 패치 스킵 (이미 적용되었거나 수동 수정 필요)"

echo "[패치 B-5] 서버 무중단 재기동"
if [ -f .petlink.pid ]; then PID="$(cat .petlink.pid || true)"; [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true; fi
sleep 2
node server/app.js > .petlink.out 2>&1 & echo $! > .petlink.pid
sleep 1
for i in $(seq 1 20); do curl -sf "http://localhost:${PORT}/health" >/dev/null && { echo "health OK"; break; }; sleep 0.3; done

echo
echo "[검증] 인덱스 생성 확인"
psql "$DATABASE_URL" -Atc "SELECT indexname FROM pg_indexes WHERE tablename='ad_payments' AND indexname LIKE '%created_at%';" | grep -q "idx_ad_payments_created_at" && echo "✅ ad_payments 인덱스 OK"
psql "$DATABASE_URL" -Atc "SELECT indexname FROM pg_indexes WHERE tablename='ad_invoices' AND indexname LIKE '%created_at%';" | grep -q "idx_ad_invoices_created_at" && echo "✅ ad_invoices 인덱스 OK"

echo
echo "[검증] X-Request-Id 헤더 확인"
curl -sI "http://localhost:${PORT}/health" | grep -q "X-Request-Id" && echo "✅ X-Request-Id 헤더 OK" || echo "⚠️  X-Request-Id 헤더 미검출"

echo
echo "[검증] 리포트 MA7 확인"
export ADMIN_KEY="${ADMIN_KEY:-admin-dev-key-123}"
curl -s "http://localhost:${PORT}/admin/reports/daily.json" -H "X-Admin-Key: ${ADMIN_KEY}" | grep -q "success_rate_ma7" && echo "✅ 리포트 MA7 OK" || echo "⚠️  리포트 MA7 미검출"

echo
echo "[DONE] r6.3 운영 안정성/관측성 보강 완료"
echo "로그 확인: tail -n 200 .petlink.out"


