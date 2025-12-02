const client = require('prom-client');
const enabled = String(process.env.METRICS_ENABLED || 'true') === 'true';

if (enabled) {
  client.collectDefaultMetrics(); // process, eventloop, heap 등
}

module.exports = { client, enabled };

