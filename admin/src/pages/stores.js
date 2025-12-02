/**
 * 어드민: 매장 목록 페이지
 * P0: D1 - 매장 목록/상태 관리
 */

export default function render() {
  return `
    <div class="admin-page-stores">
      <div class="page-header">
        <h1>매장 관리</h1>
      </div>

      <!-- 검색/필터 -->
      <div class="filters">
        <input type="text" id="search-input" placeholder="매장명/이메일/전화 검색" onkeyup="handleSearch()">
        <select id="status-filter" onchange="loadStores()">
          <option value="">전체</option>
          <option value="active">활성</option>
          <option value="inactive">비활성</option>
          <option value="pending">대기</option>
        </select>
      </div>

      <!-- 매장 목록 -->
      <div id="stores-list" class="stores-list">
        <div class="loading">매장 목록을 불러오는 중...</div>
      </div>
    </div>
  `;
}

export function init() {
  loadStores();
}

/**
 * 매장 목록 로드
 */
window.loadStores = async function() {
  const search = document.getElementById('search-input').value;
  const status = document.getElementById('status-filter').value;
  
  try {
    const api = (await import('../services/api.js')).default;
    const stores = await api.getAdminStores(search, status);
    
    const storesList = document.getElementById('stores-list');
    if (stores.stores && stores.stores.length > 0) {
      storesList.innerHTML = `
        <table class="stores-table">
          <thead>
            <tr>
              <th>ID</th>
              <th>매장명</th>
              <th>이메일</th>
              <th>전화</th>
              <th>플랜</th>
              <th>구독 상태</th>
              <th>매장 상태</th>
              <th>작업</th>
            </tr>
          </thead>
          <tbody>
            ${stores.stores.map(store => `
              <tr>
                <td>${store.id}</td>
                <td>${store.name}</td>
                <td>${store.email}</td>
                <td>${store.phone || '-'}</td>
                <td>${store.plan_code || '-'}</td>
                <td>${store.subscription_status || '-'}</td>
                <td>${store.store_status || 'active'}</td>
                <td>
                  <button class="btn-small" onclick="updateStoreStatus(${store.id}, 'active')">승인</button>
                  <button class="btn-small" onclick="updateStoreStatus(${store.id}, 'inactive')">정지</button>
                </td>
              </tr>
            `).join('')}
          </tbody>
        </table>
      `;
    } else {
      storesList.innerHTML = '<p>매장이 없습니다.</p>';
    }
  } catch (error) {
    document.getElementById('stores-list').innerHTML = '<p>매장 목록을 불러올 수 없습니다.</p>';
  }
};

/**
 * 검색 처리
 */
window.handleSearch = function() {
  // 디바운스 (300ms)
  clearTimeout(window.searchTimeout);
  window.searchTimeout = setTimeout(() => {
    loadStores();
  }, 300);
};

/**
 * 매장 상태 변경
 */
window.updateStoreStatus = async function(id, status) {
  try {
    const api = (await import('../services/api.js')).default;
    const result = await api.updateStoreStatus(id, status);
    
    if (result.ok) {
      alert('상태가 변경되었습니다.');
      loadStores();
    }
  } catch (error) {
    alert('상태 변경 중 오류가 발생했습니다.');
  }
};

