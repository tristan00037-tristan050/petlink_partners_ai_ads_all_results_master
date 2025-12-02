CREATE TABLE IF NOT EXISTS oidc_jwks_cache(
  issuer TEXT NOT NULL,
  kid TEXT NOT NULL,
  jwk JSONB NOT NULL,
  fetched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY(issuer, kid)
);
CREATE TABLE IF NOT EXISTS oidc_key_state(
  issuer TEXT PRIMARY KEY,
  last_kids TEXT[] NOT NULL DEFAULT '{}',
  changed_at TIMESTAMPTZ
);
