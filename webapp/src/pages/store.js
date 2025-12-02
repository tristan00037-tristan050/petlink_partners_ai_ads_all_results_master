/**
 * My Store 페이지
 * P0: A2 - My Store(필수 필드)
 */

export default function render() {
  return `
    <div class="page-store">
      <div class="page-header">
        <h1>My Store</h1>
        <p>매장 정보를 입력해 주세요</p>
      </div>

      <form id="store-form" class="form">
        <div class="form-group">
          <label for="store-name">매장명 <span class="required">*</span></label>
          <input type="text" id="store-name" name="name" required placeholder="예: 반려동물 분양센터">
        </div>

        <div class="form-group">
          <label for="store-address">주소</label>
          <input type="text" id="store-address" name="address" placeholder="예: 서울시 강남구 테헤란로 123">
        </div>

        <div class="form-group">
          <label for="store-phone">연락처</label>
          <input type="tel" id="store-phone" name="phone" placeholder="예: 02-1234-5678">
        </div>

        <div class="form-group">
          <label for="store-business-hours">영업시간</label>
          <input type="text" id="store-business-hours" name="business_hours" placeholder="예: 평일 10:00-20:00">
        </div>

        <div class="form-group">
          <label for="store-short-description">한 줄 소개 <span class="required">*</span></label>
          <input type="text" id="store-short-description" name="short_description" required placeholder="예: 책임 있는 분양을 약속합니다" maxlength="100">
        </div>

        <div class="form-group">
          <label for="store-description">본문</label>
          <textarea id="store-description" name="description" rows="5" placeholder="매장에 대한 상세 설명을 입력하세요"></textarea>
        </div>

        <div class="form-group">
          <label for="store-images">대표 이미지 (1~4장)</label>
          <input type="file" id="store-images" name="images" multiple accept="image/*">
          <div id="image-preview" class="image-preview"></div>
        </div>

        <div id="form-errors" class="form-errors"></div>

        <div class="form-actions">
          <button type="submit" class="btn-primary">저장</button>
          <button type="button" class="btn-secondary" onclick="router.navigate('home')">취소</button>
        </div>
      </form>
    </div>
  `;
}

export function init() {
  loadStoreData();
  setupForm();
  setupImagePreview();
}

/**
 * 기존 매장 데이터 로드
 */
async function loadStoreData() {
  try {
    const api = (await import('../services/api.js')).default;
    const store = await api.getStore();
    
    if (store.store) {
      document.getElementById('store-name').value = store.store.name || '';
      document.getElementById('store-address').value = store.store.address || '';
      document.getElementById('store-phone').value = store.store.phone || '';
      document.getElementById('store-business-hours').value = store.store.business_hours || '';
      document.getElementById('store-short-description').value = store.store.short_description || '';
      document.getElementById('store-description').value = store.store.description || '';
    }
  } catch (error) {
    // 매장 정보가 없으면 새로 생성
    console.log('매장 정보 없음, 새로 생성');
  }
}

/**
 * 폼 설정
 */
function setupForm() {
  const form = document.getElementById('store-form');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const formData = new FormData(form);
    const storeData = {
      name: formData.get('name'),
      address: formData.get('address'),
      phone: formData.get('phone'),
      business_hours: formData.get('business_hours'),
      short_description: formData.get('short_description'),
      description: formData.get('description'),
      images: [] // TODO: 이미지 업로드 처리
    };

    // 필수 필드 검증
    if (!storeData.name || !storeData.short_description) {
      showError('매장명과 한 줄 소개는 필수입니다.');
      return;
    }

    try {
      const api = (await import('../services/api.js')).default;
      const result = await api.updateStore(storeData);
      
      if (result.ok) {
        alert('매장 정보가 저장되었습니다.');
        router.navigate('home');
      }
    } catch (error) {
      if (error.code === 'STORE_PROFILE_INCOMPLETE') {
        showError(error.message);
      } else {
        showError('저장 중 오류가 발생했습니다.');
      }
    }
  });
}

/**
 * 이미지 미리보기 설정
 */
function setupImagePreview() {
  const imageInput = document.getElementById('store-images');
  const preview = document.getElementById('image-preview');
  
  imageInput.addEventListener('change', (e) => {
    const files = Array.from(e.target.files).slice(0, 4);
    preview.innerHTML = '';
    
    files.forEach(file => {
      const reader = new FileReader();
      reader.onload = (e) => {
        const img = document.createElement('img');
        img.src = e.target.result;
        img.className = 'preview-image';
        preview.appendChild(img);
      };
      reader.readAsDataURL(file);
    });
  });
}

/**
 * 에러 표시
 */
function showError(message) {
  const errorDiv = document.getElementById('form-errors');
  errorDiv.innerHTML = `<div class="error-message">${message}</div>`;
}

