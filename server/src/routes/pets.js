const express = require('express');
const { pool } = require('../lib/db');
const { requireAuth } = require('../mw/authn');
const { assertCreatePet } = require('../schema/pet');

const router = express.Router();

async function ensureMember(storeId, user) {
  const q = `
    SELECT 1 FROM stores s
    LEFT JOIN store_members m ON m.store_id=s.id AND m.user_id=$2 AND m.role IN ('owner','manager')
    WHERE s.id=$1 AND s.tenant=$3 AND (s.owner_user_id=$2 OR m.user_id=$2)
    LIMIT 1`;
  const { rows } = await pool.query(q, [storeId, user.sub, user.tenant]);
  return rows.length > 0;
}

/** 반려동물 등록 */
router.post('/stores/:id/pets', requireAuth, async (req, res, next) => {
  try {
    const storeId = parseInt(req.params.id, 10);
    if (!(await ensureMember(storeId, req.user))) {
      return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    }
    const { name, species, breed, age_months, sex } = assertCreatePet(req.body);
    const q = `
      INSERT INTO pets (store_id, name, species, breed, age_months, sex)
      VALUES ($1,$2,$3,$4,$5,$6)
      RETURNING id, name, species, status, created_at
    `;
    const { rows } = await pool.query(q, [storeId, name, species, breed, age_months, sex]);
    res.json({ ok: true, pet: rows[0] });
  } catch (err) { next(err); }
});

/** 매장별 반려동물 목록 */
router.get('/stores/:id/pets', requireAuth, async (req, res, next) => {
  try {
    const storeId = parseInt(req.params.id, 10);
    if (!(await ensureMember(storeId, req.user))) {
      return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    }
    const { rows } = await pool.query(
      'SELECT id, name, species, breed, age_months, status, created_at FROM pets WHERE store_id=$1 ORDER BY id DESC',
      [storeId]
    );
    res.json({ ok: true, items: rows });
  } catch (err) { next(err); }
});

module.exports = router;

