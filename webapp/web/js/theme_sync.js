// theme_sync.js - Landing CSS 변수를 UI 테마에 자동 반영

(function() {
    'use strict';
    
    /**
     * Landing CSS에서 CSS 변수를 추출하여 UI 테마에 반영
     */
    function syncThemeFromLanding() {
        // Landing CSS 파일 로드 확인
        const landingStylesheet = Array.from(document.styleSheets).find(sheet => {
            try {
                return sheet.href && sheet.href.includes('landing.css');
            } catch (e) {
                return false;
            }
        });
        
        if (!landingStylesheet) {
            console.warn('Landing CSS를 찾을 수 없습니다. 기본값을 사용합니다.');
            return;
        }
        
        // CSS 변수 추출
        const root = document.documentElement;
        const computedStyle = getComputedStyle(root);
        
        // --landing-* 변수 찾기
        const landingVars = [
            '--landing-bg',
            '--landing-surface',
            '--landing-primary',
            '--landing-primary-hover',
            '--landing-secondary',
            '--landing-text',
            '--landing-text-muted',
            '--landing-text-light',
            '--landing-border',
            '--landing-border-hover',
            '--landing-success',
            '--landing-warning',
            '--landing-error',
            '--landing-info',
            '--landing-font-family',
            '--landing-font-size-base',
            '--landing-font-size-sm',
            '--landing-font-size-lg',
            '--landing-font-size-xl',
            '--landing-font-size-2xl',
            '--landing-font-size-3xl'
        ];
        
        landingVars.forEach(varName => {
            const value = computedStyle.getPropertyValue(varName).trim();
            if (value) {
                // --ui-* 변수로 매핑
                const uiVarName = varName.replace('--landing-', '--ui-');
                root.style.setProperty(uiVarName, value);
            }
        });
        
        console.log('테마 동기화 완료: Landing CSS 변수를 UI 테마에 반영했습니다.');
    }
    
    /**
     * DOMContentLoaded 또는 즉시 실행
     */
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', syncThemeFromLanding);
    } else {
        syncThemeFromLanding();
    }
    
    /**
     * 동적 스타일시트 로드 감지 (선택사항)
     */
    const observer = new MutationObserver(() => {
        syncThemeFromLanding();
    });
    
    observer.observe(document.head, {
        childList: true,
        subtree: true
    });
    
    // 전역으로 노출 (필요 시)
    window.ThemeSync = {
        sync: syncThemeFromLanding
    };
})();


