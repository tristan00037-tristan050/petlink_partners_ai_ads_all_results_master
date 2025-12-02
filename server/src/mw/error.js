module.exports = function errorMw(err, req, res, next) {
  console.error('[ERROR]', err);
  res.status(err.status || 500).json({
    ok: false,
    code: err.code || 'INTERNAL_ERROR',
    message: err.message || '서버 오류가 발생했습니다.',
  });
};

