const appUser = require('./app_user_guard');
const { requireAny } = require('./require_role');
// 결제 퍼블릭 라우트 보호(OWNER 필요)
function mountBillingPolicies(app){
  app.use('/ads/billing/payment-methods', appUser, requireAny(['OWNER']));
  app.use('/ads/billing/charge',           appUser, requireAny(['OWNER']));
  // 인보이스 생성(POST /ads/billing/invoices)도 OWNER
  app.use('/ads/billing/invoices',         appUser, requireAny(['OWNER'], { onlyMethods:['POST','PUT','DELETE'] }));
}
// 프로필 수정은 MANAGER/OWNER
function mountProfilePolicies(app){
  const guard = [appUser, requireAny(['MANAGER','OWNER'], { onlyMethods:['PUT','POST','DELETE'] })];
  app.use('/advertiser/profile', ...guard);
}
module.exports = { mountBillingPolicies, mountProfilePolicies };

