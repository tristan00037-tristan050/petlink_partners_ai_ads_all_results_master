const crypto = require('crypto');

function verifyHmac(raw, sig, secret) {
  if (!sig || !secret) return false;
  const mac = crypto.createHmac('sha256', secret).update(raw).digest('hex');
  try { return crypto.timingSafeEqual(Buffer.from(mac), Buffer.from(sig)); }
  catch { return false; }
}

module.exports = { verifyHmac };

