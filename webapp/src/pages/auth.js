/**
 * 로그인/회원가입 페이지
 * P0: 로그인 플로우 변경 (홈으로 이동)
 */

export default function render() {
  return `
    <div class="page-auth">
      <div class="auth-card">
        <h1>펫링크 파트너스</h1>
        <p>분양광고를 시작하세요</p>

        <!-- 탭 메뉴 -->
        <div class="auth-tabs">
          <button class="auth-tab active" onclick="switchTab('signup')">회원가입</button>
          <button class="auth-tab" onclick="switchTab('login')">로그인</button>
        </div>

        <div id="error-message" class="error-message"></div>

        <!-- 회원가입 폼 -->
        <form id="signup-form" class="auth-form active" onsubmit="handleSignup(event)">
          <div class="form-group">
            <label for="signup-email">이메일 (아이디)</label>
            <input type="email" id="signup-email" name="email" required placeholder="example@email.com">
          </div>

          <div class="form-group">
            <label for="signup-password">비밀번호</label>
            <input type="password" id="signup-password" name="password" required placeholder="8자 이상 입력하세요" minlength="8">
          </div>

          <div class="form-group">
            <label for="signup-password-confirm">비밀번호 확인</label>
            <input type="password" id="signup-password-confirm" name="password-confirm" required placeholder="비밀번호를 다시 입력하세요">
          </div>

          <button type="submit" class="btn-primary">회원가입</button>
        </form>

        <!-- 로그인 폼 -->
        <form id="login-form" class="auth-form" onsubmit="handleLogin(event)">
          <div class="form-group">
            <label for="login-email">이메일 (아이디)</label>
            <input type="email" id="login-email" name="email" required placeholder="example@email.com">
          </div>

          <div class="form-group">
            <label for="login-password">비밀번호</label>
            <input type="password" id="login-password" name="password" required placeholder="비밀번호를 입력하세요">
          </div>

          <button type="submit" class="btn-primary">로그인</button>
        </form>
      </div>
    </div>
  `;
}

export function init() {
  // URL 파라미터 확인 (mode=login)
  const urlParams = new URLSearchParams(window.location.search);
  if (urlParams.get('mode') === 'login') {
    switchTab('login');
  }
}

/**
 * 탭 전환
 */
window.switchTab = function(tab) {
  document.querySelectorAll('.auth-tab').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.auth-form').forEach(f => f.classList.remove('active'));
  
  if (tab === 'login') {
    document.querySelectorAll('.auth-tab')[1].classList.add('active');
    document.getElementById('login-form').classList.add('active');
  } else {
    document.querySelectorAll('.auth-tab')[0].classList.add('active');
    document.getElementById('signup-form').classList.add('active');
  }
  
  document.getElementById('error-message').textContent = '';
};

/**
 * 회원가입 처리
 */
window.handleSignup = async function(e) {
  e.preventDefault();
  
  const email = document.getElementById('signup-email').value;
  const password = document.getElementById('signup-password').value;
  const passwordConfirm = document.getElementById('signup-password-confirm').value;
  
  if (password !== passwordConfirm) {
    showError('비밀번호가 일치하지 않습니다.');
    return;
  }

  try {
    const api = (await import('../services/api.js')).default;
    const result = await api.signup(email, password);
    
    if (result.ok) {
      // 회원가입 성공 → 홈으로 이동
      router.navigate('home');
    }
  } catch (error) {
    if (error.code === '409') {
      showError('이미 존재하는 이메일입니다.');
    } else {
      showError('회원가입 중 오류가 발생했습니다.');
    }
  }
};

/**
 * 로그인 처리
 */
window.handleLogin = async function(e) {
  e.preventDefault();
  
  const email = document.getElementById('login-email').value;
  const password = document.getElementById('login-password').value;

  try {
    const api = (await import('../services/api.js')).default;
    const result = await api.login(email, password);
    
    if (result.ok) {
      // 로그인 성공 → 홈으로 이동 (차단하지 않음)
      router.navigate('home');
    }
  } catch (error) {
    if (error.code === '401') {
      showError('이메일 또는 비밀번호가 올바르지 않습니다.');
    } else {
      showError('로그인 중 오류가 발생했습니다.');
    }
  }
};

/**
 * 에러 표시
 */
function showError(message) {
  const errorDiv = document.getElementById('error-message');
  errorDiv.textContent = message;
  errorDiv.style.display = 'block';
}

