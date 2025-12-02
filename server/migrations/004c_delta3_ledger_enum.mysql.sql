-- 004c_delta3_ledger_enum.mysql.sql (v2.3 Δ3)
-- media_wallet_ledger transaction_type enum 확장

ALTER TABLE media_wallet_ledger
  MODIFY COLUMN transaction_type ENUM(
    'PLAN_CREDIT', 'TRIAL_CREDIT', 'TOPUP', 'SPEND', 'REFUND', 
    'CONTRACT_CREDIT', 'REVERSAL', 'PENALTY_DEBIT'
  ) NOT NULL;


