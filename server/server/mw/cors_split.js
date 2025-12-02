const cors = require("cors");

const APP_ORIGIN = process.env.APP_ORIGIN || "http://localhost:3000";
const ADMIN_ORIGIN = process.env.ADMIN_ORIGIN || "http://localhost:8000";

// App CORS 미들웨어
const appCORS = cors({
  origin: (origin, callback) => {
    if (!origin || origin === APP_ORIGIN || origin.startsWith(APP_ORIGIN)) {
      callback(null, true);
    } else {
      callback(new Error("CORS_NOT_ALLOWED"));
    }
  },
  credentials: true
});

// Admin CORS 미들웨어
const adminCORS = cors({
  origin: (origin, callback) => {
    if (!origin || origin === ADMIN_ORIGIN || origin.startsWith(ADMIN_ORIGIN)) {
      callback(null, true);
    } else {
      callback(new Error("CORS_NOT_ALLOWED"));
    }
  },
  credentials: true
});

module.exports = { appCORS, adminCORS };
