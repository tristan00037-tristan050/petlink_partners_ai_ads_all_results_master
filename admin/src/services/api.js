/**
 * P0 Admin API 클라이언트
 */

const API_BASE_URL = process.env.API_BASE_URL || 'http://localhost:5903';
const ADMIN_KEY = process.env.ADMIN_KEY || 'admin-dev-key-123';

class AdminAPI {
  constructor() {
    this.baseURL = API_BASE_URL;
    this.adminKey = ADMIN_KEY;
  }

  async request(endpoint, options = {}) {
    const url = `${this.baseURL}${endpoint}`;
    const headers = {
      'Content-Type': 'application/json',
      'X-Admin-Key': this.adminKey,
      ...options.headers
    };

    try {
      const response = await fetch(url, {
        ...options,
        headers
      });

      const data = await response.json();

      if (!response.ok) {
        throw new APIError(data.code || 'UNKNOWN_ERROR', data.message || '알 수 없는 오류가 발생했습니다.', response.status);
      }

      return data;
    } catch (error) {
      if (error instanceof APIError) {
        throw error;
      }
      throw new APIError('NETWORK_ERROR', '네트워크 오류가 발생했습니다.', 0);
    }
  }

  // ============================================================================
  // Admin Stores API
  // ============================================================================

  async getAdminStores(q, status) {
    const params = new URLSearchParams();
    if (q) params.append('q', q);
    if (status) params.append('status', status);
    
    const query = params.toString();
    return this.request(`/admin/stores${query ? '?' + query : ''}`);
  }

  async updateStoreStatus(id, status) {
    return this.request(`/admin/stores/${id}/status`, {
      method: 'PATCH',
      body: JSON.stringify({ status })
    });
  }

  // ============================================================================
  // Admin Campaigns API
  // ============================================================================

  async getAdminCampaigns(q, status, storeId) {
    const params = new URLSearchParams();
    if (q) params.append('q', q);
    if (status) params.append('status', status);
    if (storeId) params.append('store_id', storeId);
    
    const query = params.toString();
    return this.request(`/admin/campaigns${query ? '?' + query : ''}`);
  }

  async getAdminCampaign(id) {
    return this.request(`/admin/campaigns/${id}`);
  }

  async approveCampaign(id) {
    return this.request(`/admin/campaigns/${id}/approve`, {
      method: 'PATCH'
    });
  }

  async rejectCampaign(id, comment) {
    return this.request(`/admin/campaigns/${id}/reject`, {
      method: 'PATCH',
      body: JSON.stringify({ comment })
    });
  }
}

class APIError extends Error {
  constructor(code, message, status) {
    super(message);
    this.name = 'APIError';
    this.code = code;
    this.status = status;
  }
}

export default new AdminAPI();
export { APIError };

