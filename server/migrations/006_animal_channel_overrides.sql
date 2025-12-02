-- 006_animal_channel_overrides.sql
-- 동물별 채널 예외 설정

CREATE TABLE IF NOT EXISTS animal_channel_overrides (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    animal_id BIGINT NOT NULL UNIQUE,
    ig_enabled TINYINT(1) NULL COMMENT '인스타그램/페이스북 예외 (NULL=매장 기본값 사용)',
    tt_enabled TINYINT(1) NULL COMMENT '틱톡 예외 (NULL=매장 기본값 사용)',
    yt_enabled TINYINT(1) NULL COMMENT '유튜브 예외 (NULL=매장 기본값 사용)',
    kakao_enabled TINYINT(1) NULL COMMENT '카카오 예외 (NULL=매장 기본값 사용)',
    naver_enabled TINYINT(1) NULL COMMENT '네이버 예외 (NULL=매장 기본값 사용)',
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (animal_id) REFERENCES animals(id) ON DELETE CASCADE,
    INDEX idx_animal_id (animal_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


