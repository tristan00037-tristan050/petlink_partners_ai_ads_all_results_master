// 간단한 서버 테스트
console.log('=== P0 서버 모듈 테스트 ===\n');

const tests = [
  { name: 'express', mod: 'express' },
  { name: 'cors', mod: 'cors' },
  { name: 'pg', mod: 'pg' },
  { name: 'node-cron', mod: 'node-cron' },
  { name: 'helmet', mod: 'helmet' },
  { name: 'express-rate-limit', mod: 'express-rate-limit' },
  { name: 'lib/db', mod: './lib/db' },
  { name: 'lib/policy_engine', mod: './lib/policy_engine' },
  { name: 'mw/auth', mod: './mw/auth' },
  { name: 'mw/cors_split', mod: './mw/cors_split' },
  { name: 'mw/admin_gate', mod: './mw/admin_gate' },
  { name: 'routes/auth', mod: './routes/auth' },
  { name: 'routes/stores', mod: './routes/stores' },
  { name: 'routes/plans', mod: './routes/plans' },
  { name: 'routes/campaigns', mod: './routes/campaigns' },
  { name: 'routes/admin_stores', mod: './routes/admin_stores' },
  { name: 'routes/admin_campaigns', mod: './routes/admin_campaigns' },
  { name: 'bootstrap/billing_scheduler', mod: './bootstrap/billing_scheduler' }
];

let passed = 0;
let failed = 0;

tests.forEach(({ name, mod }) => {
  try {
    require(mod);
    console.log(`✅ ${name}`);
    passed++;
  } catch (e) {
    console.error(`❌ ${name}: ${e.message}`);
    failed++;
  }
});

console.log(`\n=== 결과: ${passed} 통과, ${failed} 실패 ===`);
