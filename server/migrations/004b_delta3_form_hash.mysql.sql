-- 004b_delta3_form_hash.mysql.sql (v2.3 Δ3)
-- form_hash 컬럼 추가 (이미 있으면 스킵)

ALTER TABLE contract_documents
  ADD COLUMN IF NOT EXISTS form_hash CHAR(64) NULL COMMENT '양식 해시(최초 원본 양식 검증용)';

CREATE INDEX IF NOT EXISTS idx_contract_documents_form_hash ON contract_documents(form_hash);


