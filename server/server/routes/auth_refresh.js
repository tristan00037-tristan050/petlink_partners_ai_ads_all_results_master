const express = require("express");
const crypto = require("crypto");
const db = require("../lib/db");
const { sign, verify } = require("../lib/auth/jwt");
const r = express.Router();

function randToken(){ return crypto.randomBytes(32).toString("hex"); }

r.post("/login", express.json(), async (req,res)=>{
  const { email, password } = req.body||{};
  const uq = await db.q(`SELECT id,advertiser_id,pw_salt,pw_hash FROM advertiser_users WHERE email=$1`, [String(email||"").toLowerCase()]);
  if(!uq.rows.length) return res.status(401).json({ ok:false, code:"AUTH_FAIL" });
  const u = uq.rows[0];
  const crypto = require("crypto");
  // 비밀번호 검증: sha256(password + salt) 방식
  const calc = crypto.createHash("sha256").update(String(password||"") + u.pw_salt).digest("hex");
  if (calc !== u.pw_hash) return res.status(401).json({ ok:false, code:"AUTH_FAIL" });

  const access_token = sign({ user_id:u.id, advertiser_id:u.advertiser_id }, 900);     // 15m
  const refresh_token = randToken();                                                   // 30d
  const exp = new Date(Date.now() + 30*24*3600*1000);
  await db.q(`INSERT INTO advertiser_sessions(user_id, refresh_token, expires_at) VALUES ($1,$2,$3)
              ON CONFLICT (refresh_token) DO NOTHING`, [u.id, refresh_token, exp]);
  res.json({ ok:true, access_token, refresh_token, expires_at: exp.toISOString() });
});

r.post("/refresh", express.json(), async (req,res)=>{
  const { refresh_token } = req.body||{};
  if(!refresh_token) return res.status(400).json({ ok:false, code:"REFRESH_REQUIRED" });
  const q = await db.q(`SELECT s.id, s.user_id, u.advertiser_id, s.expires_at FROM advertiser_sessions s
                        JOIN advertiser_users u ON u.id=s.user_id
                        WHERE s.refresh_token=$1`, [refresh_token]);
  if(!q.rows.length) return res.status(401).json({ ok:false, code:"REFRESH_INVALID" });
  const s = q.rows[0];
  if (new Date(s.expires_at) < new Date()) return res.status(401).json({ ok:false, code:"REFRESH_EXPIRED" });
  const access_token = sign({ user_id:s.user_id, advertiser_id:s.advertiser_id }, 900);
  const new_refresh = crypto.randomBytes(32).toString("hex");
  const exp = new Date(Date.now() + 30*24*3600*1000);
  await db.q(`UPDATE advertiser_sessions SET refresh_token=$2, rotated_at=now(), expires_at=$3 WHERE id=$1`,
             [s.id, new_refresh, exp]);
  res.json({ ok:true, access_token, refresh_token:new_refresh, expires_at:exp.toISOString() });
});

r.post("/logout", express.json(), async (req,res)=>{
  const { refresh_token } = req.body||{};
  if(!refresh_token) return res.status(400).json({ ok:false, code:"REFRESH_REQUIRED" });
  await db.q(`DELETE FROM advertiser_sessions WHERE refresh_token=$1`, [refresh_token]);
  res.json({ ok:true });
});

module.exports = r;
