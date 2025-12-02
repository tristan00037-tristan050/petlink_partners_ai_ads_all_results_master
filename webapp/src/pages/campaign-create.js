/**
 * 캠페인 생성 페이지
 * P0: A4 - 광고 생성 플로우
 */

export default function render() {
  return `
    <div class="page-campaign-create">
      <div class="page-header">
        <h1>광고 생성</h1>
        <p>반려동물 정보와 콘텐츠를 입력하세요</p>
      </div>

      <!-- 단계 표시 -->
      <div class="steps">
        <div class="step active" data-step="1">반려동물 선택</div>
        <div class="step" data-step="2">콘텐츠 업로드</div>
        <div class="step" data-step="3">AI 카피 생성</div>
        <div class="step" data-step="4">채널 선택</div>
        <div class="step" data-step="5">미리보기</div>
      </div>

      <form id="campaign-form" class="form">
        <!-- Step 1: 반려동물 선택 -->
        <div id="step-1" class="form-step active">
          <h2>반려동물 선택</h2>
          <div class="form-group">
            <label for="pet-select">반려동물 <span class="required">*</span></label>
            <select id="pet-select" name="pet_id" required>
              <option value="">선택하세요</option>
            </select>
            <button type="button" class="btn-secondary" onclick="showPetRegister()">새로 등록</button>
          </div>
        </div>

        <!-- Step 2: 콘텐츠 업로드 -->
        <div id="step-2" class="form-step">
          <h2>콘텐츠 업로드</h2>
          <div class="form-group">
            <label for="campaign-images">사진 (1~5장) <span class="required">*</span></label>
            <input type="file" id="campaign-images" name="images" multiple accept="image/*" required>
            <div id="image-preview" class="image-preview"></div>
          </div>
          <div class="form-group">
            <label for="campaign-videos">영상 (선택, 최대 3개)</label>
            <input type="file" id="campaign-videos" name="videos" multiple accept="video/*">
            <div id="video-preview" class="video-preview"></div>
          </div>
        </div>

        <!-- Step 3: AI 카피 생성 -->
        <div id="step-3" class="form-step">
          <h2>AI 카피 생성</h2>
          <div class="form-group">
            <label for="campaign-title">제목 <span class="required">*</span> (최대 30자)</label>
            <input type="text" id="campaign-title" name="title" required maxlength="30" placeholder="예: 사랑스러운 포메라니안">
            <div class="char-count"><span id="title-count">0</span>/30</div>
          </div>
          <div class="form-group">
            <label for="campaign-body">본문 <span class="required">*</span></label>
            <textarea id="campaign-body" name="body" required rows="6" placeholder="AI가 자동으로 생성합니다. 수정 가능합니다."></textarea>
          </div>
          <div class="form-group">
            <label for="campaign-hashtags">해시태그 (5~10개)</label>
            <input type="text" id="campaign-hashtags" name="hashtags" placeholder="#책임분양 #반려가족 (쉼표로 구분)">
            <div class="form-hint">AI가 자동으로 생성합니다. 수정 가능합니다.</div>
          </div>
          <button type="button" class="btn-primary" onclick="generateAICopy()">AI 카피 생성</button>
        </div>

        <!-- Step 4: 채널 선택 -->
        <div id="step-4" class="form-step">
          <h2>채널 선택</h2>
          <div class="channels-grid">
            <label class="channel-checkbox">
              <input type="checkbox" name="channels" value="instagram">
              <span>인스타그램</span>
            </label>
            <label class="channel-checkbox">
              <input type="checkbox" name="channels" value="facebook">
              <span>페이스북</span>
            </label>
            <label class="channel-checkbox">
              <input type="checkbox" name="channels" value="tiktok">
              <span>틱톡</span>
            </label>
            <label class="channel-checkbox">
              <input type="checkbox" name="channels" value="youtube">
              <span>유튜브</span>
            </label>
            <label class="channel-checkbox">
              <input type="checkbox" name="channels" value="kakao">
              <span>카카오</span>
            </label>
            <label class="channel-checkbox">
              <input type="checkbox" name="channels" value="naver">
              <span>네이버</span>
            </label>
          </div>
        </div>

        <!-- Step 5: 미리보기 -->
        <div id="step-5" class="form-step">
          <h2>미리보기</h2>
          <div id="campaign-preview" class="campaign-preview"></div>
        </div>

        <div id="form-errors" class="form-errors"></div>

        <div class="form-actions">
          <button type="button" class="btn-secondary" id="prev-btn" onclick="prevStep()" style="display: none;">이전</button>
          <button type="button" class="btn-primary" id="next-btn" onclick="nextStep()">다음</button>
          <button type="submit" class="btn-primary" id="submit-btn" style="display: none;">저장</button>
        </div>
      </form>
    </div>
  `;
}

let currentStep = 1;
const totalSteps = 5;

export function init() {
  loadPets();
  setupForm();
  setupImagePreview();
  setupVideoPreview();
  setupTitleCounter();
}

/**
 * 반려동물 목록 로드
 */
async function loadPets() {
  try {
    // TODO: API에서 반려동물 목록 가져오기
    const petSelect = document.getElementById('pet-select');
    petSelect.innerHTML = '<option value="">선택하세요</option>';
    // 스텁 데이터
    petSelect.innerHTML += '<option value="1">포메라니안 (3개월, 수컷)</option>';
  } catch (error) {
    console.error('반려동물 목록 로드 실패:', error);
  }
}

/**
 * 폼 설정
 */
function setupForm() {
  const form = document.getElementById('campaign-form');
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const formData = new FormData(form);
    const campaignData = {
      pet_id: parseInt(formData.get('pet_id')),
      title: formData.get('title'),
      body: formData.get('body'),
      hashtags: parseHashtags(formData.get('hashtags')),
      images: [], // TODO: 이미지 업로드 처리
      videos: [], // TODO: 영상 업로드 처리
      channels: formData.getAll('channels')
    };

    // 검증
    if (!campaignData.pet_id || !campaignData.title || !campaignData.body || campaignData.channels.length === 0) {
      showError('필수 필드를 모두 입력해 주세요.');
      return;
    }

    try {
      const api = (await import('../services/api.js')).default;
      const result = await api.createCampaign(campaignData);
      
      if (result.ok) {
        alert('광고가 생성되었습니다.');
        router.navigate('campaigns');
      }
    } catch (error) {
      if (error.code === 'STORE_PROFILE_INCOMPLETE') {
        showError('매장 정보를 먼저 완성해 주세요.');
        router.navigate('store');
      } else {
        showError('광고 생성 중 오류가 발생했습니다.');
      }
    }
  });
}

/**
 * 해시태그 파싱
 */
function parseHashtags(hashtagsStr) {
  if (!hashtagsStr) return [];
  return hashtagsStr.split(/[,\s]+/).filter(h => h.trim().length > 0);
}

/**
 * 이미지 미리보기 설정
 */
function setupImagePreview() {
  const imageInput = document.getElementById('campaign-images');
  const preview = document.getElementById('image-preview');
  
  imageInput.addEventListener('change', (e) => {
    const files = Array.from(e.target.files).slice(0, 5);
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
 * 영상 미리보기 설정
 */
function setupVideoPreview() {
  const videoInput = document.getElementById('campaign-videos');
  const preview = document.getElementById('video-preview');
  
  videoInput.addEventListener('change', (e) => {
    const files = Array.from(e.target.files).slice(0, 3);
    preview.innerHTML = '';
    
    files.forEach(file => {
      const video = document.createElement('video');
      video.src = URL.createObjectURL(file);
      video.controls = true;
      video.className = 'preview-video';
      preview.appendChild(video);
    });
  });
}

/**
 * 제목 글자 수 카운터
 */
function setupTitleCounter() {
  const titleInput = document.getElementById('campaign-title');
  const counter = document.getElementById('title-count');
  
  titleInput.addEventListener('input', (e) => {
    counter.textContent = e.target.value.length;
  });
}

/**
 * AI 카피 생성
 */
window.generateAICopy = async function() {
  const petId = document.getElementById('pet-select').value;
  if (!petId) {
    alert('반려동물을 먼저 선택해 주세요.');
    return;
  }

  // TODO: 실제 AI API 호출
  // 스텁: 샘플 카피 생성
  const sampleTitle = '사랑스러운 포메라니안을 찾아주세요';
  const sampleBody = '가족에게 책임 있는 만남을 약속드립니다. 방문 상담 환영합니다. 건강한 반려동물과 함께 행복한 시간을 보내세요.';
  const sampleHashtags = '#책임분양 #반려가족 #방문상담 #반려동물 #분양';

  document.getElementById('campaign-title').value = sampleTitle;
  document.getElementById('campaign-body').value = sampleBody;
  document.getElementById('campaign-hashtags').value = sampleHashtags;
  document.getElementById('title-count').textContent = sampleTitle.length;
};

/**
 * 다음 단계
 */
window.nextStep = function() {
  if (currentStep < totalSteps) {
    // 현재 단계 검증
    if (!validateStep(currentStep)) {
      return;
    }
    
    currentStep++;
    updateSteps();
  }
};

/**
 * 이전 단계
 */
window.prevStep = function() {
  if (currentStep > 1) {
    currentStep--;
    updateSteps();
  }
};

/**
 * 단계 업데이트
 */
function updateSteps() {
  // 단계 표시 업데이트
  document.querySelectorAll('.step').forEach((step, idx) => {
    if (idx + 1 <= currentStep) {
      step.classList.add('active');
    } else {
      step.classList.remove('active');
    }
  });

  // 폼 단계 표시/숨김
  document.querySelectorAll('.form-step').forEach((step, idx) => {
    if (idx + 1 === currentStep) {
      step.classList.add('active');
    } else {
      step.classList.remove('active');
    }
  });

  // 버튼 표시
  document.getElementById('prev-btn').style.display = currentStep > 1 ? 'block' : 'none';
  document.getElementById('next-btn').style.display = currentStep < totalSteps ? 'block' : 'none';
  document.getElementById('submit-btn').style.display = currentStep === totalSteps ? 'block' : 'none';

  // 마지막 단계에서 미리보기 업데이트
  if (currentStep === totalSteps) {
    updatePreview();
  }
}

/**
 * 단계 검증
 */
function validateStep(step) {
  switch (step) {
    case 1:
      const petId = document.getElementById('pet-select').value;
      if (!petId) {
        showError('반려동물을 선택해 주세요.');
        return false;
      }
      break;
    case 2:
      const images = document.getElementById('campaign-images').files;
      if (images.length === 0) {
        showError('사진을 최소 1장 업로드해 주세요.');
        return false;
      }
      break;
    case 3:
      const title = document.getElementById('campaign-title').value;
      const body = document.getElementById('campaign-body').value;
      if (!title || !body) {
        showError('제목과 본문을 입력해 주세요.');
        return false;
      }
      break;
    case 4:
      const channels = document.querySelectorAll('input[name="channels"]:checked');
      if (channels.length === 0) {
        showError('최소 1개 채널을 선택해 주세요.');
        return false;
      }
      break;
  }
  return true;
}

/**
 * 미리보기 업데이트
 */
function updatePreview() {
  const preview = document.getElementById('campaign-preview');
  const title = document.getElementById('campaign-title').value;
  const body = document.getElementById('campaign-body').value;
  const hashtags = document.getElementById('campaign-hashtags').value;
  const channels = Array.from(document.querySelectorAll('input[name="channels"]:checked')).map(c => c.value);
  
  preview.innerHTML = `
    <div class="preview-card">
      <h3>${title}</h3>
      <p>${body}</p>
      <div class="preview-hashtags">${hashtags}</div>
      <div class="preview-channels">채널: ${channels.join(', ')}</div>
    </div>
  `;
}

/**
 * 반려동물 등록 페이지로 이동
 */
window.showPetRegister = function() {
  // TODO: 반려동물 등록 모달 또는 페이지로 이동
  alert('반려동물 등록 기능은 준비 중입니다.');
};

/**
 * 에러 표시
 */
function showError(message) {
  const errorDiv = document.getElementById('form-errors');
  errorDiv.innerHTML = `<div class="error-message">${message}</div>`;
}

