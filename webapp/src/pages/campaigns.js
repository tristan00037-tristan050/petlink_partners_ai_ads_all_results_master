/**
 * 광고 관리 페이지
 * P0: A5 - 광고 관리(리스트/상세/상태변경)
 */

export default function render() {
  return `
    <div class="page-campaigns">
      <div class="page-header">
        <h1>광고 관리</h1>
        <button class="btn-primary" onclick="router.navigate('campaign-create')">새 광고 만들기</button>
      </div>

      <!-- 필터 -->
      <div class="filters">
        <select id="status-filter" onchange="loadCampaigns()">
          <option value="">전체</option>
          <option value="DRAFT">초안</option>
          <option value="SUBMITTED">제출됨</option>
          <option value="PENDING_REVIEW">심사중</option>
          <option value="APPROVED">승인됨</option>
          <option value="REJECTED_BY_POLICY">정책 위반</option>
          <option value="RUNNING">집행중</option>
          <option value="PAUSED">일시중지</option>
          <option value="PAUSED_BY_BILLING">결제 정지</option>
          <option value="STOPPED">종료</option>
        </select>
      </div>

      <!-- 광고 리스트 -->
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
  const statusFilter = document.getElementById('status-filter').value;
  
  try {
    const api = (await import('../services/api.js')).default;
    const campaigns = await api.getCampaigns(statusFilter);
    
    const campaignsList = document.getElementById('campaigns-list');
    if (campaigns.campaigns && campaigns.campaigns.length > 0) {
      campaignsList.innerHTML = campaigns.campaigns.map(campaign => `
        <div class="campaign-card" onclick="showCampaignDetail(${campaign.id})">
          <div class="campaign-thumbnail">
            ${campaign.images && campaign.images.length > 0 ? `<img src="${campaign.images[0]}" alt="${campaign.title}">` : '<div class="no-image">이미지 없음</div>'}
          </div>
          <div class="campaign-info">
            <h3>${campaign.title}</h3>
            <p class="campaign-status status-${campaign.status.toLowerCase()}">${getStatusLabel(campaign.status)}</p>
            <p class="campaign-channels">${campaign.channels.join(', ')}</p>
            <p class="campaign-date">${new Date(campaign.created_at).toLocaleDateString()}</p>
          </div>
          <div class="campaign-actions">
            ${getActionButtons(campaign.status)}
          </div>
        </div>
      `).join('');
    } else {
      campaignsList.innerHTML = '<p>등록된 광고가 없습니다.</p>';
    }
  } catch (error) {
    document.getElementById('campaigns-list').innerHTML = '<p>광고 목록을 불러올 수 없습니다.</p>';
  }
};

/**
 * 상태 라벨
 */
function getStatusLabel(status) {
  const labels = {
    'DRAFT': '초안',
    'SUBMITTED': '제출됨',
    'PENDING_REVIEW': '심사중',
    'APPROVED': '승인됨',
    'REJECTED_BY_POLICY': '정책 위반',
    'RUNNING': '집행중',
    'PAUSED': '일시중지',
    'PAUSED_BY_BILLING': '결제 정지',
    'STOPPED': '종료'
  };
  return labels[status] || status;
}

/**
 * 액션 버튼
 */
function getActionButtons(status) {
  const buttons = [];
  
  if (status === 'DRAFT') {
    buttons.push('<button class="btn-small" onclick="event.stopPropagation(); submitCampaign(id)">제출</button>');
  } else if (status === 'RUNNING') {
    buttons.push('<button class="btn-small" onclick="event.stopPropagation(); pauseCampaign(id)">일시중지</button>');
    buttons.push('<button class="btn-small" onclick="event.stopPropagation(); stopCampaign(id)">종료</button>');
  } else if (status === 'PAUSED') {
    buttons.push('<button class="btn-small" onclick="event.stopPropagation(); resumeCampaign(id)">재개</button>');
  }
  
  return buttons.join('');
}

/**
 * 광고 상세 보기
 */
window.showCampaignDetail = async function(id) {
  try {
    const api = (await import('../services/api.js')).default;
    const campaign = await api.getCampaign(id);
    
    // 모달 또는 상세 페이지로 표시
    const modal = document.createElement('div');
    modal.className = 'modal';
    modal.innerHTML = `
      <div class="modal-content">
        <div class="modal-header">
          <h2>${campaign.campaign.title}</h2>
          <button onclick="this.closest('.modal').remove()">&times;</button>
        </div>
        <div class="modal-body">
          <p><strong>상태:</strong> ${getStatusLabel(campaign.campaign.status)}</p>
          <p><strong>채널:</strong> ${campaign.campaign.channels.join(', ')}</p>
          <p><strong>본문:</strong></p>
          <p>${campaign.campaign.body}</p>
          ${campaign.campaign.policy_violations && campaign.campaign.policy_violations.length > 0 ? `
            <div class="policy-violations">
              <h3>정책 위반 사항</h3>
              ${campaign.campaign.policy_violations.map(v => `
                <div class="violation-item">
                  <p><strong>${v.type}</strong>: ${v.message}</p>
                  ${v.suggested_body ? `<p>제안: ${v.suggested_body}</p>` : ''}
                </div>
              `).join('')}
            </div>
          ` : ''}
        </div>
        <div class="modal-footer">
          ${getActionButtons(campaign.campaign.status)}
        </div>
      </div>
    `;
    document.body.appendChild(modal);
  } catch (error) {
    alert('광고 상세 정보를 불러올 수 없습니다.');
  }
};

/**
 * 캠페인 상태 변경
 */
async function updateCampaignStatus(id, action) {
  try {
    const api = (await import('../services/api.js')).default;
    const result = await api.updateCampaignStatus(id, action);
    
    if (result.ok) {
      alert('상태가 변경되었습니다.');
      loadCampaigns();
    }
  } catch (error) {
    alert('상태 변경 중 오류가 발생했습니다.');
  }
}

window.submitCampaign = (id) => updateCampaignStatus(id, 'submit');
window.pauseCampaign = (id) => updateCampaignStatus(id, 'pause');
window.resumeCampaign = (id) => updateCampaignStatus(id, 'resume');
window.stopCampaign = (id) => updateCampaignStatus(id, 'stop');

