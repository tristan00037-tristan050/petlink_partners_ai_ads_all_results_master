-- 004a_delta3_bonus_policy_update.mysql.sql (v2.3 Δ3)
-- 보너스 정책 기본값 업데이트

UPDATE contract_bonus_policies
SET 
  per_contract_max = 3,
  monthly_pages_max = 100,
  upload_window_hours_photo = 48,
  credit_valid_months = 3,
  dup_similarity_auto_review = 0.90,
  dup_similarity_pending = 0.80,
  updated_at = CURRENT_TIMESTAMP
WHERE org_id IS NULL;

-- 기본값이 없으면 삽입
INSERT INTO contract_bonus_policies (
  org_id, per_page_amount, per_contract_max, monthly_pages_max, 
  upload_window_hours_photo, ocr_threshold, 
  dup_similarity_auto_review, dup_similarity_pending, credit_valid_months
)
SELECT NULL, 1000, 3, 100, 48, 0.95, 0.90, 0.80, 3
WHERE NOT EXISTS (
  SELECT 1 FROM contract_bonus_policies WHERE org_id IS NULL
);


