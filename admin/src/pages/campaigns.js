/**
 * 어드민: 광고 목록 페이지
 * P0: D2 - 광고 목록 → 상세(승인/반려)
 */

export default function render() {
  return `
    <div class="admin-page-campaigns">
      <div class="page-header">
        <h1>광고 관리</h1>
      </div>

      <!-- 검색/필터 -->
      <div class="filters">
        <input type="text" id="search-input" placeholder="제목/매장명 검색" onkeyup="handleSearch()">
        <select id="status-filter" onchange="loadCampaigns()">
          <option value="">전체</option>
          <option value="PENDING_REVIEW">심사중</option>
          <option value="APPROVED">승인됨</option>
          <option value="REJECTED_BY_POLICY">정책 위반</option>
        </select>
      </div>

      <!-- 광고 목록 -->
      <div id="campaigns-list" class="campaigns-list">
        <div class="loading">광고 목록을 불러오는 중...</div>
      </div>
    </div>
  `;
}

export function init() {
  loadCampaigns();
}

/**
 * 광고 목록 로드
 */
window.loadCampaigns = async function() {
  const search = document.getElementById('search-input').value;
  const status = document.getElementById('status-filter').value;
  
  try {
    const api = (await import('../services/api.js')).default;
    const campaigns = await api.getAdminCampaigns(search, status);
    
    const campaignsList = document.getElementById('campaigns-list');
    if (campaigns.campaigns && campaigns.campaigns.length > 0) {
      campaignsList.innerHTML = campaigns.campaigns.map(campaign => `
        <div class="campaign-card" onclick="showCampaignDetail(${campaign.id})">
          <div class="campaign-thumbnail">
            ${campaign.thumbnail ? `<img src="${campaign.thumbnail}" alt="${campaign.title}">` : '<div class="no-image">이미지 없음</div>'}
          </div>
          <div class="campaign-info">
            <h3>${campaign.title}</h3>
            <p>매장: ${campaign.store_name}</p>
            <p>상태: ${campaign.status}</p>
            <p>채널: ${campaign.channels.join(', ')}</p>
            ${campaign.policy_violations && campaign.policy_violations.length > 0 ? 
              `<p class="violations-count">정책 위반: ${campaign.policy_violations.length}건</p>` : ''}
          </div>
        </div>
      `).join('');
    } else {
      campaignsList.innerHTML = '<p>광고가 없습니다.</p>';
    }
  } catch (error) {
    document.getElementById('campaigns-list').innerHTML = '<p>광고 목록을 불러올 수 없습니다.</p>';
  }
};

/**
 * 검색 처리
 */
window.handleSearch = function() {
  clearTimeout(window.searchTimeout);
  window.searchTimeout = setTimeout(() => {
    loadCampaigns();
  }, 300);
};

/**
 * 광고 상세 보기 (승인/반려)
 */
window.showCampaignDetail = async function(id) {
  try {
    const api = (await import('../services/api.js')).default;
    const campaign = await api.getAdminCampaign(id);
    
    // 모달 표시
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.innerHTML = `
      <div class="modal-content large">
        <div class="modal-header">
          <h2>${campaign.campaign.title}</h2>
          <button onclick="this.closest('.modal').remove()">&times;</button>
        </div>
        <div class="modal-body">
          <div class="campaign-detail">
            <p><strong>매장:</strong> ${campaign.campaign.store_name}</p>
            <p><strong>상태:</strong> ${campaign.campaign.status}</p>
            <p><strong>채널:</strong> ${campaign.campaign.channels.join(', ')}</p>
            <p><strong>본문:</strong></p>
            <p>${campaign.campaign.body}</p>
          </div>
          
          ${campaign.campaign.policy_violations && campaign.campaign.policy_violations.length > 0 ? `
            <div class="policy-violations">
              <h3>정책 위반 사항</h3>
              ${campaign.campaign.policy_violations.map(v => `
                <div class="violation-item">
                  <p><strong>${v.type}</strong> (${v.field}): ${v.message}</p>
                  ${v.keyword ? `<p>키워드: ${v.keyword}</p>` : ''}
                  ${v.code ? `<p>코드: ${v.code}, 점수: ${v.score}</p>` : ''}
                  ${v.suggested_body ? `<p>제안 문구: ${v.suggested_body}</p>` : ''}
                  ${v.suggested_hashtags && v.suggested_hashtags.length > 0 ? 
                    `<p>제안 해시태그: ${v.suggested_hashtags.join(', ')}</p>` : ''}
                </div>
              `).join('')}
            </div>
          ` : ''}
        </div>
        <div class="modal-footer">
          ${campaign.campaign.status === 'PENDING_REVIEW' ? `
            <button class="btn-primary" onclick="approveCampaign(${id})">승인</button>
            <button class="btn-secondary" onclick="showRejectForm(${id})">반려</button>
          ` : ''}
        </div>
      </div>
    `;
    document.body.appendChild(modal);
  } catch (error) {
    alert('광고 상세 정보를 불러올 수 없습니다.');
  }
};

/**
 * 광고 승인
 */
window.approveCampaign = async function(id) {
  try {
    const api = (await import('../services/api.js')).default;
    const result = await api.approveCampaign(id);
    
    if (result.ok) {
      alert('광고가 승인되었습니다.');
      document.querySelector('.modal').remove();
      loadCampaigns();
    }
  } catch (error) {
    alert('승인 중 오류가 발생했습니다.');
  }
};

/**
 * 반려 폼 표시
 */
window.showRejectForm = function(id) {
  const comment = prompt('반려 사유를 입력하세요:');
  if (comment) {
    rejectCampaign(id, comment);
  }
};

/**
 * 광고 반려
 */
async function rejectCampaign(id, comment) {
  try {
    const api = (await import('../services/api.js')).default;
    const result = await api.rejectCampaign(id, comment);
    
    if (result.ok) {
      alert('광고가 반려되었습니다.');
      document.querySelector('.modal').remove();
      loadCampaigns();
    }
  } catch (error) {
    alert('반려 중 오류가 발생했습니다.');
  }
}

