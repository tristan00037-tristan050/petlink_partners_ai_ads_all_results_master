const { DateTime } = require('luxon');

const TZ = process.env.TIMEZONE || 'Asia/Seoul';

function today() {
    return DateTime.now().setZone(TZ).toISODate();
}

function now() {
    return DateTime.now().setZone(TZ).toISO();
}

function parseDate(dateStr) {
    return DateTime.fromISO(dateStr, { zone: TZ });
}

module.exports = { today, now, parseDate, TZ };
