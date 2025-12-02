/**
 * 플랜 선택 페이지
 * P0: A3 - 플랜 선택/변경(P0 화면만)
 */

export default function render() {
  return `
    <div class="page-plans">
      <div class="page-header">
        <h1>요금제 선택</h1>
        <p>원하는 요금제를 선택하세요</p>
      </div>

      <div id="plans-grid" class="plans-grid">
        <div class="loading">요금제 목록을 불러오는 중...</div>
      </div>

      <div id="current-subscription" class="current-subscription" style="display: none;">
        <h2>현재 요금제</h2>
        <div id="subscription-info" class="card"></div>
      </div>
    </div>
  `;
}

export function init() {
  loadPlans();
  loadCurrentSubscription();
}

/**
 * 요금제 목록 로드
 */
async function loadPlans() {
  try {
    const api = (await import('../services/api.js')).default;
    const plans = await api.getPlans();
    
    const plansGrid = document.getElementById('plans-grid');
    if (plans.plans && plans.plans.length > 0) {
      plansGrid.innerHTML = plans.plans.map(plan => `
        <div class="plan-card">
          <h3>${plan.name}</h3>
          <div class="plan-price">₩${plan.price.toLocaleString()}</div>
          <div class="plan-period">/월</div>
          <div class="plan-budget">광고비 ₩${plan.ad_budget.toLocaleString()} 포함</div>
          <ul class="plan-features">
            ${plan.features.map(f => `<li>${f}</li>`).join('')}
          </ul>
          <button class="btn-primary" onclick="selectPlan(${plan.id})">선택하기</button>
        </div>
      `).join('');
    } else {
      plansGrid.innerHTML = '<p>요금제 목록을 불러올 수 없습니다.</p>';
    }
  } catch (error) {
    document.getElementById('plans-grid').innerHTML = '<p>요금제 목록을 불러올 수 없습니다.</p>';
  }
}

/**
 * 현재 구독 정보 로드
 */
async function loadCurrentSubscription() {
  try {
    const api = (await import('../services/api.js')).default;
    const subscription = await api.getSubscription();
    
    if (subscription.subscription) {
      const currentDiv = document.getElementById('current-subscription');
      const infoDiv = document.getElementById('subscription-info');
      
      currentDiv.style.display = 'block';
      infoDiv.innerHTML = `
        <p><strong>플랜:</strong> ${subscription.subscription.plan_code}</p>
        <p><strong>상태:</strong> ${subscription.subscription.status}</p>
        <p><strong>다음 결제일:</strong> ${subscription.subscription.next_billing_date}</p>
      `;
    }
  } catch (error) {
    // 구독 정보 없음 (정상)
  }
}

/**
 * 플랜 선택
 */
window.selectPlan = async function(planId) {
  try {
    const api = (await import('../services/api.js')).default;
    const result = await api.selectPlan(planId);
    
    if (result.ok) {
      alert('요금제가 선택되었습니다.');
      loadCurrentSubscription();
    }
  } catch (error) {
    alert('요금제 선택 중 오류가 발생했습니다.');
  }
};

