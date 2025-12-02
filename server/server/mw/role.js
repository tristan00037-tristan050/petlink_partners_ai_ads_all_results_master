/**
 * X-Admin-Role: 'superadmin' | 'operator'
 * - superadmin: CSV Import, 대량수정 허용
 * - operator: 단건 수정만
 */
exports.requireRole = (role) => (req,res,next)=>{
  const cur = String(req.get('X-Admin-Role')||'').toLowerCase();
  if(cur !== String(role).toLowerCase()){
    return res.status(403).json({ ok:false, code:'ROLE_REQUIRED', required: role });
  }
  next();
};
