const repo = require('./repo');

async function log(store_id, type, payload) {
    try {
        await repo.auditLog(store_id, type, payload);
    } catch (e) {
        console.error('Audit log error:', e);
    }
}

module.exports = { log };
