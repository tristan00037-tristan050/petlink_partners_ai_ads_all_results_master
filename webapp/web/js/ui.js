// ui.js - 간단한 UI 헬퍼 함수

/**
 * 토스트 메시지 표시
 */
function showToast(message, type = 'info', duration = 3000) {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    
    document.body.appendChild(toast);
    
    setTimeout(() => {
        toast.style.animation = 'toastSlideIn 0.3s ease reverse';
        setTimeout(() => {
            document.body.removeChild(toast);
        }, 300);
    }, duration);
}

/**
 * 로딩 상태 표시
 */
function setLoading(element, isLoading) {
    if (isLoading) {
        element.disabled = true;
        element.dataset.originalText = element.textContent;
        element.textContent = '처리 중...';
    } else {
        element.disabled = false;
        if (element.dataset.originalText) {
            element.textContent = element.dataset.originalText;
            delete element.dataset.originalText;
        }
    }
}

/**
 * 폼 검증
 */
function validateForm(form) {
    const inputs = form.querySelectorAll('[required]');
    let isValid = true;
    
    inputs.forEach(input => {
        if (!input.value.trim()) {
            isValid = false;
            input.classList.add('error');
            const errorMsg = document.createElement('div');
            errorMsg.className = 'form-error';
            errorMsg.textContent = '필수 항목입니다.';
            input.parentElement.appendChild(errorMsg);
        } else {
            input.classList.remove('error');
            const errorMsg = input.parentElement.querySelector('.form-error');
            if (errorMsg) {
                errorMsg.remove();
            }
        }
    });
    
    return isValid;
}

/**
 * 금지어 검사 (클라이언트 측)
 */
function checkBannedWords(text) {
    const bannedWords = [
        '가격', '재고', '즉시분양', '택배', '배송',
        '급처', '싸게', '대량', '도매', '분양'
    ];
    
    const found = bannedWords.filter(word => text.includes(word));
    return {
        valid: found.length === 0,
        words: found
    };
}

/**
 * 파일 크기 포맷
 */
function formatFileSize(bytes) {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
}

/**
 * 숫자 포맷 (천 단위 콤마)
 */
function formatNumber(num) {
    return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/**
 * 전역으로 노출
 */
window.UI = {
    showToast,
    setLoading,
    validateForm,
    checkBannedWords,
    formatFileSize,
    formatNumber
};


