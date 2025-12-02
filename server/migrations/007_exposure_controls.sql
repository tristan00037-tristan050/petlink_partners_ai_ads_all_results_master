-- 007_exposure_controls.sql (v2.4.1)
-- 노출 제어 관련 스키마

-- stores 테이블에 반경 컬럼 추가
ALTER TABLE stores 
  ADD COLUMN IF NOT EXISTS radius_km TINYINT NOT NULL DEFAULT 6 COMMENT '기본 6km (권장 5~7km)';

-- 노출 가중치 테이블
CREATE TABLE IF NOT EXISTS exposure_weights (
  store_id BIGINT NOT NULL PRIMARY KEY,
  mon DECIMAL(6,2) NOT NULL DEFAULT 1.00 COMMENT '월요일 가중치',
  tue DECIMAL(6,2) NOT NULL DEFAULT 1.00 COMMENT '화요일 가중치',
  wed DECIMAL(6,2) NOT NULL DEFAULT 1.00 COMMENT '수요일 가중치',
  thu DECIMAL(6,2) NOT NULL DEFAULT 1.05 COMMENT '목요일 가중치',
  fri DECIMAL(6,2) NOT NULL DEFAULT 1.15 COMMENT '금요일 가중치',
  sat DECIMAL(6,2) NOT NULL DEFAULT 1.30 COMMENT '토요일 가중치',
  sun DECIMAL(6,2) NOT NULL DEFAULT 1.25 COMMENT '일요일 가중치',
  holiday DECIMAL(6,2) NOT NULL DEFAULT 1.30 COMMENT '공휴일 가중치',
  holidays_json JSON NULL COMMENT '공휴일 목록 ["2025-01-01", "2025-03-01", ...]',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 채널별 CPM 추적 테이블 (최근 7일 평균 계산용)
CREATE TABLE IF NOT EXISTS channel_cpm_daily (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  store_id BIGINT NOT NULL,
  channel ENUM('INSTAGRAM', 'FACEBOOK', 'TIKTOK', 'YOUTUBE', 'GOOGLE', 'KAKAO', 'NAVER') NOT NULL,
  date DATE NOT NULL,
  cpm DECIMAL(10,2) NOT NULL COMMENT 'CPM (1000회 노출당 비용)',
  impressions INT DEFAULT 0 COMMENT '실제 노출 수',
  spend DECIMAL(10,2) DEFAULT 0 COMMENT '실제 지출',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY unique_store_channel_date (store_id, channel, date),
  INDEX idx_store_id (store_id),
  INDEX idx_channel (channel),
  INDEX idx_date (date),
  FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 일일 예산 배정 테이블
CREATE TABLE IF NOT EXISTS daily_budget_allocations (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  store_id BIGINT NOT NULL,
  date DATE NOT NULL,
  total_budget DECIMAL(10,2) NOT NULL COMMENT '해당 날짜 총 예산',
  instagram_budget DECIMAL(10,2) DEFAULT 0,
  facebook_budget DECIMAL(10,2) DEFAULT 0,
  tiktok_budget DECIMAL(10,2) DEFAULT 0,
  youtube_budget DECIMAL(10,2) DEFAULT 0,
  google_budget DECIMAL(10,2) DEFAULT 0,
  kakao_budget DECIMAL(10,2) DEFAULT 0,
  naver_budget DECIMAL(10,2) DEFAULT 0,
  weight_applied DECIMAL(6,2) NOT NULL COMMENT '적용된 가중치',
  is_holiday TINYINT(1) DEFAULT 0 COMMENT '공휴일 여부',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_store_date (store_id, date),
  INDEX idx_store_id (store_id),
  INDEX idx_date (date),
  FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


