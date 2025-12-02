module.exports = () => (req,res,next) => {
  const id = req.headers['x-request-id'] || Math.random().toString(36).slice(2);
  res.setHeader('X-Request-Id', id);
  req.requestId = id;
  next();
};
