const { fetch } = require('undici') || globalThis.fetch;

// OIDC Discovery
async function discovery(issuer) {
  if (!issuer) throw new Error('issuer required');
  const url = `${issuer}/.well-known/openid-configuration`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Discovery failed: ${res.status}`);
  return await res.json();
}

// JWKS 조회
async function jwks(issuer) {
  if (!issuer) throw new Error('issuer required');
  const disc = await discovery(issuer);
  const jwksUrl = disc.jwks_uri;
  if (!jwksUrl) throw new Error('jwks_uri not found');
  const res = await fetch(jwksUrl);
  if (!res.ok) throw new Error(`JWKS fetch failed: ${res.status}`);
  return await res.json();
}

module.exports = { discovery, jwks };

