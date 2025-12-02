function assertCreatePet(body) {
  if (!body || typeof body !== 'object') throw new Error('잘못된 요청');
  const name = String(body.name || '').trim();
  const species = String(body.species || '').trim();
  if (!name) throw new Error('name 필수');
  if (!species) throw new Error('species 필수');
  const breed = body.breed ? String(body.breed) : null;
  const age_months = Number.isFinite(body.age_months) ? Math.max(0, parseInt(body.age_months,10)) : 0;
  const sex = body.sex ? String(body.sex) : null;
  return { name, species, breed, age_months, sex };
}

module.exports = { assertCreatePet };

