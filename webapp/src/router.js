/**
 * P0 웹앱 라우터
 * SPA 라우팅 시스템
 */

class Router {
  constructor() {
    this.routes = {};
    this.currentRoute = null;
    this.init();
  }

  init() {
    // 해시 변경 감지
    window.addEventListener('hashchange', () => this.handleRoute());
    // 초기 로드
    this.handleRoute();
  }

  /**
   * 라우트 등록
   * @param {string} path - 라우트 경로
   * @param {Function} handler - 라우트 핸들러
   */
  route(path, handler) {
    this.routes[path] = handler;
  }

  /**
   * 라우트 처리
   */
  handleRoute() {
    const hash = window.location.hash.slice(1) || 'home';
    const handler = this.routes[hash] || this.routes['404'];
    
    if (handler) {
      this.currentRoute = hash;
      handler();
    }
  }

  /**
   * 네비게이션
   * @param {string} path - 이동할 경로
   */
  navigate(path) {
    window.location.hash = path;
  }
}

// 전역 라우터 인스턴스
const router = new Router();

// 라우트 정의
router.route('home', () => {
  loadPage('home');
});

router.route('auth', () => {
  loadPage('auth');
});

router.route('store', () => {
  loadPage('store');
});

router.route('plans', () => {
  loadPage('plans');
});

router.route('campaigns', () => {
  loadPage('campaigns');
});

router.route('campaign-create', () => {
  loadPage('campaign-create');
});

router.route('404', () => {
  document.getElementById('app').innerHTML = '<h1>404 - 페이지를 찾을 수 없습니다</h1>';
});

/**
 * 페이지 로드
 * @param {string} pageName - 페이지 이름
 */
function loadPage(pageName) {
  const app = document.getElementById('app');
  
  // 로딩 표시
  app.innerHTML = '<div class="loading">로딩 중...</div>';
  
  // 페이지 컴포넌트 동적 로드
  import(`./pages/${pageName}.js`)
    .then(module => {
      app.innerHTML = module.default();
      // 페이지별 초기화
      if (module.init) {
        module.init();
      }
    })
    .catch(err => {
      console.error('페이지 로드 실패:', err);
      app.innerHTML = '<div class="error">페이지를 불러올 수 없습니다.</div>';
    });
}

export default router;

