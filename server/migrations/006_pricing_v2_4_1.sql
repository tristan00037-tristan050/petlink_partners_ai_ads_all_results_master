-- 006_pricing_v2_4_1.sql
-- v2.4.1 가격표 및 플랜 전환 관련 스키마

-- 플랜 테이블 업데이트 (v2.4.1 All-in 플랜)
UPDATE plans SET 
    name = 'All-in S',
    monthly_price = 200000,
    ad_budget_cap = 120000,
    platform_fee = 80000,
    platforms = 'INSTAGRAM_FACEBOOK,TIKTOK'
WHERE code = 'ALLIN_S';

UPDATE plans SET 
    name = 'All-in M',
    monthly_price = 400000,
    ad_budget_cap = 300000,
    platform_fee = 100000,
    platforms = 'INSTAGRAM_FACEBOOK,TIKTOK'
WHERE code = 'ALLIN_M';

UPDATE plans SET 
    name = 'All-in L',
    monthly_price = 800000,
    ad_budget_cap = 600000,
    platform_fee = 200000,
    platforms = 'INSTAGRAM_FACEBOOK,TIKTOK'
WHERE code = 'ALLIN_L';

UPDATE plans SET 
    name = 'All-in XL',
    monthly_price = 1500000,
    ad_budget_cap = 1100000,
    platform_fee = 400000,
    platforms = 'INSTAGRAM_FACEBOOK,TIKTOK'
WHERE code = 'ALLIN_XL';

-- 플랜 전환 이력 테이블
CREATE TABLE IF NOT EXISTS plan_switches (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    store_id BIGINT NOT NULL,
    from_plan_code VARCHAR(50) NULL,
    to_plan_code VARCHAR(50) NOT NULL,
    switched_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    switched_by BIGINT NULL COMMENT 'user_id',
    reason VARCHAR(255) NULL,
    INDEX idx_store_id (store_id),
    INDEX idx_switched_at (switched_at),
    FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 설정 테이블 (공휴일 등)
CREATE TABLE IF NOT EXISTS app_settings (
    id INT PRIMARY KEY AUTO_INCREMENT,
    key_name VARCHAR(100) NOT NULL UNIQUE,
    value_json JSON NOT NULL,
    description VARCHAR(255) NULL,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 공휴일 기본값 삽입
INSERT INTO app_settings (key_name, value_json, description) VALUES
('holidays_2025', JSON_ARRAY('2025-01-01', '2025-03-01', '2025-05-05', '2025-06-06', '2025-08-15', '2025-10-03', '2025-10-09', '2025-12-25'), '2025년 공휴일 목록')
ON DUPLICATE KEY UPDATE value_json = VALUES(value_json);


