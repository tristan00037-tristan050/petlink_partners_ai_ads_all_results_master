function pick(name) {
  const key = (name || 'mock').toLowerCase();
  if (key === 'bootpay-rest' || key === 'bootpay-sandbox') return require('./adapters/bootpay_rest');
  // mock 어댑터는 기존 경로 사용
  return require('../../adapters/billing');
}
module.exports = () => pick(process.env.BILLING_ADAPTER);
