/**
 * P0: 이미지 1차 필터
 * 업로드 시 기본 검증 (크기, 형식, 해상도)
 */

/**
 * 이미지 필터 결과
 * @typedef {Object} ImageFilterResult
 * @property {boolean} approved - 승인 여부
 * @property {Array<string>} errors - 에러 메시지 목록
 * @property {Array<string>} warnings - 경고 메시지 목록
 */

/**
 * 이미지 필터 설정
 */
const IMAGE_FILTER_CONFIG = {
  maxFileSize: 10 * 1024 * 1024, // 10MB
  allowedFormats: ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'],
  minWidth: 400,
  minHeight: 400,
  maxWidth: 5000,
  maxHeight: 5000,
  maxAspectRatio: 2.0, // 가로/세로 비율 최대 2:1
  minAspectRatio: 0.5  // 가로/세로 비율 최소 1:2
};

/**
 * 이미지 필터 클래스
 */
class ImageFilter {
  /**
   * 이미지 파일 검증
   * @param {File|Buffer} file - 이미지 파일
   * @param {Object} options - 옵션
   * @returns {Promise<ImageFilterResult>}
   */
  async validate(file, options = {}) {
    const errors = [];
    const warnings = [];
    const config = { ...IMAGE_FILTER_CONFIG, ...options };

    // 1. 파일 크기 검증
    if (file.size > config.maxFileSize) {
      errors.push(`파일 크기가 너무 큽니다. (최대 ${config.maxFileSize / 1024 / 1024}MB)`);
    }

    // 2. 파일 형식 검증
    if (!config.allowedFormats.includes(file.type)) {
      errors.push(`지원하지 않는 파일 형식입니다. (${config.allowedFormats.join(', ')}만 가능)`);
    }

    // 3. 이미지 해상도 검증 (비동기)
    try {
      const dimensions = await this.getImageDimensions(file);
      
      if (dimensions.width < config.minWidth || dimensions.height < config.minHeight) {
        errors.push(`이미지 해상도가 너무 낮습니다. (최소 ${config.minWidth}x${config.minHeight})`);
      }

      if (dimensions.width > config.maxWidth || dimensions.height > config.maxHeight) {
        warnings.push(`이미지 해상도가 권장 크기를 초과합니다. (권장 ${config.maxWidth}x${config.maxHeight})`);
      }

      const aspectRatio = dimensions.width / dimensions.height;
      if (aspectRatio > config.maxAspectRatio || aspectRatio < config.minAspectRatio) {
        warnings.push(`이미지 비율이 권장 범위를 벗어났습니다. (권장 1:1 ~ 2:1)`);
      }
    } catch (error) {
      errors.push('이미지 정보를 읽을 수 없습니다.');
    }

    return {
      approved: errors.length === 0,
      errors,
      warnings
    };
  }

  /**
   * 이미지 크기 조회
   * @param {File|Buffer} file - 이미지 파일
   * @returns {Promise<{width: number, height: number}>}
   */
  async getImageDimensions(file) {
    return new Promise((resolve, reject) => {
      // Node.js 환경에서는 sharp 또는 image-size 사용
      // 브라우저 환경에서는 Image 객체 사용
      if (typeof window !== 'undefined') {
        // 브라우저 환경
        const img = new Image();
        const url = URL.createObjectURL(file);
        img.onload = () => {
          URL.revokeObjectURL(url);
          resolve({ width: img.width, height: img.height });
        };
        img.onerror = reject;
        img.src = url;
      } else {
        // Node.js 환경
        try {
          const sizeOf = require('image-size');
          const dimensions = sizeOf(file.buffer || file);
          resolve({ width: dimensions.width, height: dimensions.height });
        } catch (error) {
          // image-size가 없으면 기본값 반환
          resolve({ width: 0, height: 0 });
        }
      }
    });
  }

  /**
   * 여러 이미지 일괄 검증
   * @param {Array<File|Buffer>} files - 이미지 파일 배열
   * @param {Object} options - 옵션
   * @returns {Promise<Array<ImageFilterResult>>}
   */
  async validateBatch(files, options = {}) {
    return Promise.all(files.map(file => this.validate(file, options)));
  }
}

module.exports = new ImageFilter();

