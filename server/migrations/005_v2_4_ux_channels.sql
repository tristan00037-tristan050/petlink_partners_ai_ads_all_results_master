-- 005_v2_4_ux_channels.sql (v2.4)
-- UX 채널 수집 테이블 (유튜브/카카오/네이버)

CREATE TABLE IF NOT EXISTS ux_channels (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  store_id BIGINT NOT NULL,
  channel_type ENUM('YOUTUBE', 'KAKAO', 'NAVER') NOT NULL,
  channel_id VARCHAR(255) NOT NULL COMMENT '채널 ID 또는 URL',
  channel_name VARCHAR(255) NULL,
  subscriber_count INT NULL,
  video_count INT NULL,
  last_sync_at DATETIME NULL,
  sync_status ENUM('ACTIVE', 'PAUSED', 'ERROR') DEFAULT 'ACTIVE',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_store_channel (store_id, channel_type, channel_id),
  INDEX idx_store_id (store_id),
  INDEX idx_channel_type (channel_type),
  INDEX idx_sync_status (sync_status),
  FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 채널 콘텐츠 수집 테이블
CREATE TABLE IF NOT EXISTS ux_channel_contents (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  channel_id BIGINT NOT NULL,
  external_id VARCHAR(255) NOT NULL COMMENT '외부 플랫폼 콘텐츠 ID',
  title VARCHAR(500) NOT NULL,
  description TEXT NULL,
  url VARCHAR(512) NOT NULL,
  thumbnail_url VARCHAR(512) NULL,
  view_count INT DEFAULT 0,
  like_count INT DEFAULT 0,
  comment_count INT DEFAULT 0,
  published_at DATETIME NOT NULL,
  collected_at DATETIME NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_channel_content (channel_id, external_id),
  INDEX idx_channel_id (channel_id),
  INDEX idx_published_at (published_at),
  INDEX idx_collected_at (collected_at),
  FOREIGN KEY (channel_id) REFERENCES ux_channels(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 채널 인사이트 집계 테이블
CREATE TABLE IF NOT EXISTS ux_channel_insights (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  channel_id BIGINT NOT NULL,
  date DATE NOT NULL,
  views INT DEFAULT 0,
  likes INT DEFAULT 0,
  comments INT DEFAULT 0,
  shares INT DEFAULT 0,
  subscribers_gained INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_channel_date (channel_id, date),
  INDEX idx_channel_id (channel_id),
  INDEX idx_date (date),
  FOREIGN KEY (channel_id) REFERENCES ux_channels(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


