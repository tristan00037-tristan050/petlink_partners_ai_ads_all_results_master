function assertCreateStore(body) {
  if (!body || typeof body !== 'object') throw new Error('잘못된 요청');
  const name = String(body.name || '').trim();
  if (!name) throw new Error('name 필수');
  const address = body.address ? String(body.address) : null;
  const phone = body.phone ? String(body.phone) : null;
  return { name, address, phone };
}

function assertSubscribe(body) {
  if (!body || typeof body !== 'object') throw new Error('잘못된 요청');
  const plan_code = String(body.plan_code || '').trim();
  if (!plan_code) throw new Error('plan_code 필수');
  return { plan_code };
}

module.exports = { assertCreateStore, assertSubscribe };

