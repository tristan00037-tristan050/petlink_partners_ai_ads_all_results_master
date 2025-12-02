-- 004d_delta3_expiry_jobs.mysql.sql (v2.3 Δ3)
-- 크레딧 만료 처리용 잡 테이블

CREATE TABLE IF NOT EXISTS credit_expiry_jobs (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  store_id BIGINT NOT NULL,
  ledger_entry_id BIGINT NOT NULL,
  expiry_date DATE NOT NULL,
  processed_at DATETIME NULL,
  status ENUM('PENDING', 'PROCESSED', 'FAILED') DEFAULT 'PENDING',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_store_id (store_id),
  INDEX idx_expiry_date (expiry_date),
  INDEX idx_status (status),
  FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE,
  FOREIGN KEY (ledger_entry_id) REFERENCES media_wallet_ledger(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


