/**
 * P0 API 클라이언트
 * OpenAPI 기반 API 호출 래퍼
 */

const API_BASE_URL = process.env.API_BASE_URL || 'http://localhost:5903';

class API {
  constructor() {
    this.baseURL = API_BASE_URL;
    this.token = localStorage.getItem('auth_token');
  }

  /**
   * 인증 토큰 설정
   */
  setToken(token) {
    this.token = token;
    if (token) {
      localStorage.setItem('auth_token', token);
    } else {
      localStorage.removeItem('auth_token');
    }
  }

  /**
   * 기본 fetch 래퍼
   */
  async request(endpoint, options = {}) {
    const url = `${this.baseURL}${endpoint}`;
    const headers = {
      'Content-Type': 'application/json',
      ...options.headers
    };

    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }

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
  // Auth API
  // ============================================================================

  async signup(email, password, storeName) {
    const data = await this.request('/auth/signup', {
      method: 'POST',
      body: JSON.stringify({ email, password, store_name: storeName })
    });
    
    if (data.token) {
      this.setToken(data.token);
    }
    
    return data;
  }

  async login(email, password) {
    const data = await this.request('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password })
    });
    
    if (data.token) {
      this.setToken(data.token);
    }
    
    return data;
  }

  async getMe() {
    return this.request('/auth/me');
  }

  // ============================================================================
  // Stores API
  // ============================================================================

  async getStore() {
    return this.request('/stores/me');
  }

  async updateStore(storeData) {
    return this.request('/stores/me', {
      method: 'PUT',
      body: JSON.stringify(storeData)
    });
  }

  // ============================================================================
  // Plans API
  // ============================================================================

  async getPlans() {
    return this.request('/plans');
  }

  async getSubscription() {
    return this.request('/stores/me/plan');
  }

  async selectPlan(planId) {
    return this.request('/stores/me/plan', {
      method: 'POST',
      body: JSON.stringify({ plan_id: planId })
    });
  }

  // ============================================================================
  // Campaigns API
  // ============================================================================

  async createCampaign(campaignData) {
    return this.request('/campaigns', {
      method: 'POST',
      body: JSON.stringify(campaignData)
    });
  }

  async getCampaigns(status) {
    const query = status ? `?status=${status}` : '';
    return this.request(`/campaigns${query}`);
  }

  async getCampaign(id) {
    return this.request(`/campaigns/${id}`);
  }

  async updateCampaignStatus(id, action, petId) {
    return this.request(`/campaigns/${id}/${action}`, {
      method: 'PATCH',
      body: JSON.stringify({ pet_id: petId })
    });
  }
}

/**
 * API 에러 클래스
 */
class APIError extends Error {
  constructor(code, message, status) {
    super(message);
    this.name = 'APIError';
    this.code = code;
    this.status = status;
  }
}

export default new API();
export { APIError };

