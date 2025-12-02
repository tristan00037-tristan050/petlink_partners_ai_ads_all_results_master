const name=(process.env.BILLING_ADAPTER||'mock').toLowerCase();
module.exports = name==='bootpay-live' ? require('./bootpay_live')
  : name==='bootpay-sandbox' ? require('./bootpay_sandbox')
  : require('./mock');
