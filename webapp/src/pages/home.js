/**
 * 홈 대시보드 페이지
 * P0: A1 - 홈 대시보드 & 매장등록 유도
 */

export default function render() {
  return `
    <div class="page-home">
      <div class="home-header">
        <h1>홈 대시보드</h1>
      </div>

      <!-- 매장 미등록 배너 -->
      <div id="store-registration-banner" class="banner-warning" style="display: none;">
        <div class="banner-content">
          <h3>매장 정보를 등록해 주세요</h3>
          <p>광고를 시작하려면 먼저 매장 정보를 완성해야 합니다.</p>
          <button class="btn-primary" onclick="router.navigate('store')">지금 등록</button>
        </div>
      </div>

      <!-- 플랜 요약 -->
      <div class="section">
        <h2>현재 요금제</h2>
        <div id="plan-summary" class="card">
          <p>요금제 정보를 불러오는 중...</p>
        </div>
      </div>

      <!-- 최근 광고 -->
      <div class="section">
        <h2>최근 광고</h2>
        <div id="recent-campaigns" class="campaigns-list">
          <p>광고 목록을 불러오는 중...</p>
        </div>
      </div>
    </div>
  `;
}

export function init() {
  checkStoreStatus();
  loadPlanSummary();
  loadRecentCampaigns();
}

/**
 * 매장 등록 상태 확인
 */
async function checkStoreStatus() {
  try {
    const api = (await import('../services/api.js')).default;
    const store = await api.getStore();
    
    if (!store.store || !store.store.is_complete) {
      // 매장 미등록 또는 미완성
      document.getElementById('store-registration-banner').style.display = 'block';
    }
  } catch (error) {
    if (error.code === 'STORE_PROFILE_INCOMPLETE' || error.code === '404') {
      document.getElementById('store-registration-banner').style.display = 'block';
    }
  }
}

/**
 * 플랜 요약 로드
 */
async function loadPlanSummary() {
  try {
    const api = (await import('../services/api.js')).default;
    const subscription = await api.getSubscription();
    
    const planSummary = document.getElementById('plan-summary');
    if (subscription.subscription) {
      planSummary.innerHTML = `
        <h3>${subscription.subscription.plan_code} 플랜</h3>
        <p>다음 결제일: ${subscription.subscription.next_billing_date}</p>
        <p>상태: ${subscription.subscription.status}</p>
      `;
    } else {
      planSummary.innerHTML = '<p>요금제가 선택되지 않았습니다.</p>';
    }
  } catch (error) {
    document.getElementById('plan-summary').innerHTML = '<p>요금제 정보를 불러올 수 없습니다.</p>';
  }
}

/**
 * 최근 광고 로드
 */
async function loadRecentCampaigns() {
  try {
    const api = (await import('../services/api.js')).default;
    const campaigns = await api.getCampaigns();
    
    const campaignsList = document.getElementById('recent-campaigns');
    if (campaigns.campaigns && campaigns.campaigns.length > 0) {
      campaignsList.innerHTML = campaigns.campaigns.map(c => `
        <div class="campaign-card">
          <h4>${c.title}</h4>
          <p>상태: ${c.status}</p>
          <p>채널: ${c.channels.join(', ')}</p>
        </div>
      `).join('');
    } else {
      campaignsList.innerHTML = '<p>등록된 광고가 없습니다.</p>';
    }
  } catch (error) {
    document.getElementById('recent-campaigns').innerHTML = '<p>광고 목록을 불러올 수 없습니다.</p>';
  }
}

