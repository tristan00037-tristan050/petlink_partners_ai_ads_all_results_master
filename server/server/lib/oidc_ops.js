const db=require("./db"); const alerts=(()=>{try{return require("./alerts")}catch{return {notify:async()=>({ok:false})}}})();

async function persistJwks(issuer, jwks){
  const keys=(jwks.keys||[]).map(k=>({kid:k.kid,jwk:k}));
  for(const {kid,jwk} of keys){
    await db.q(`INSERT INTO oidc_jwks_cache(issuer,kid,jwk) VALUES($1,$2,$3)
                ON CONFLICT(issuer,kid) DO UPDATE SET jwk=EXCLUDED.jwk, fetched_at=now()`,[issuer,kid,JSON.stringify(jwk)]);
  }

  const kids=keys.map(k=>k.kid).sort();
  const st=await db.q(`SELECT last_kids FROM oidc_key_state WHERE issuer=$1`,[issuer]);
  const prev=(st.rows[0]?.last_kids)||[];
  const changed=(kids.join("|")!==prev.sort().join("|"));

  await db.q(`INSERT INTO oidc_key_state(issuer,last_kids,changed_at)
              VALUES($1,$2, CASE WHEN $3 THEN now() ELSE changed_at END)
              ON CONFLICT(issuer) DO UPDATE SET last_kids=EXCLUDED.last_kids,
                  changed_at=CASE WHEN $3 THEN now() ELSE oidc_key_state.changed_at END`,
              [issuer,kids,changed]);

  if(changed){ await alerts.notify("OIDC_KEY_ROTATION",{issuer,kids,prev}); }

  return { kids, changed };
}

async function currentKids(issuer){
  const r=await db.q(`SELECT kid FROM oidc_jwks_cache WHERE issuer=$1 ORDER BY fetched_at DESC`,[issuer]);
  return r.rows.map(x=>x.kid);
}

module.exports={ persistJwks, currentKids };
