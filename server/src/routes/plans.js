const express = require('express');
const { q } = require('../lib/db');
const router = express.Router();

router.get('/plans', async (req, res, next) => {
  try {
    const result = await q('SELECT * FROM plans ORDER BY price ASC');
    res.json({
      ok: true,
      items: result.rows.map(plan => ({
        id: plan.id,
        code: plan.code,
        name: plan.name,
        price: plan.price,
        ad_budget: plan.ad_budget,
        features: plan.features || []
      }))
    });
  } catch (err) { next(err); }
});

module.exports = router;

