module.exports = {
  async __probeToken(){ return { offline:true, has_token:false }; },
  async authorize(){ return { ok:true, provider:'mock', provider_txn_id:`mk-auth-${Date.now()}`, raw:{} }; },
  async capture({ provider_txn_id }){ return { ok:true, provider:'mock', provider_txn_id: provider_txn_id || `mk-cap-${Date.now()}`, raw:{} }; },
  async verify(){ return { ok:true, status:'CAPTURED', raw:{} }; }
};
