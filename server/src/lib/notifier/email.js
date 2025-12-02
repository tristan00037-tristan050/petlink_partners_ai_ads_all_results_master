const nodemailer = require('nodemailer');

function getTransport() {
  // 예: SMTP_URL="smtp://user:pass@mail.example.com:587"
  const url = process.env.SMTP_URL;
  if (!url) throw new Error('SMTP_URL 미설정');
  return nodemailer.createTransport(url);
}

async function sendMail({ to, subject, text, html }) {
  const from = process.env.SMTP_FROM || 'no-reply@example.com';
  const t = getTransport();
  return t.sendMail({ from, to, subject, text, html });
}

module.exports = { sendMail };

