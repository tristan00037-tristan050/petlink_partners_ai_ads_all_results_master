-- 006_store_channel_prefs.sql
-- 매장별 채널 기본값 설정

CREATE TABLE IF NOT EXISTS store_channel_prefs (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    store_id BIGINT NOT NULL UNIQUE,
    ig_enabled TINYINT(1) NOT NULL DEFAULT 1 COMMENT '인스타그램/페이스북 활성화',
    tt_enabled TINYINT(1) NOT NULL DEFAULT 1 COMMENT '틱톡 활성화',
    yt_enabled TINYINT(1) NOT NULL DEFAULT 0 COMMENT '유튜브 활성화',
    kakao_enabled TINYINT(1) NOT NULL DEFAULT 0 COMMENT '카카오 활성화',
    naver_enabled TINYINT(1) NOT NULL DEFAULT 0 COMMENT '네이버 활성화',
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
    INDEX idx_store_id (store_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 기본값: IG/TT ON, 나머지 OFF
INSERT INTO store_channel_prefs (store_id, ig_enabled, tt_enabled, yt_enabled, kakao_enabled, naver_enabled)
SELECT id, 1, 1, 0, 0, 0 FROM stores
ON DUPLICATE KEY UPDATE 
    ig_enabled = VALUES(ig_enabled),
    tt_enabled = VALUES(tt_enabled),
    yt_enabled = VALUES(yt_enabled),
    kakao_enabled = VALUES(kakao_enabled),
    naver_enabled = VALUES(naver_enabled);


