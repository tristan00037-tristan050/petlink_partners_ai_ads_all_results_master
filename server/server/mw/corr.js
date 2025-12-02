const { randomUUID } = require('crypto');
module.exports = function(req,res,next){
  const rid = req.get('X-Request-Id') || randomUUID();
  req.req_id = rid; res.setHeader('X-Request-Id', rid); next();
}
