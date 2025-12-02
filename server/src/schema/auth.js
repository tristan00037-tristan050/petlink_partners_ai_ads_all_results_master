function assertSignup(body) {
  const { email, password, tenant } = body || {};
  if (!email || typeof email !== 'string' || !email.includes('@')) {
    throw new Error('유효한 이메일이 필요합니다.');
  }
  if (!password || typeof password !== 'string' || password.length < 8) {
    throw new Error('비밀번호는 8자 이상이어야 합니다.');
  }
  return { email: String(email), password: String(password), tenant: String(tenant || 'default') };
}

module.exports = { assertSignup };

