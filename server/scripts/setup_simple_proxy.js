#!/usr/bin/env node

/**
 * 간단한 HTTP 프록시 서버
 * www.petlinkpartnet.co.kr -> localhost:5902
 */

const http = require('http');
const httpProxy = require('http-proxy-middleware');
const express = require('express');

const DOMAIN = 'www.petlinkpartnet.co.kr';
const BACKEND_PORT = process.env.PORT || 5902;
const PROXY_PORT = 80;

const app = express();

// 모든 요청을 백엔드로 프록시
app.use('/', (req, res, next) => {
  const proxy = httpProxy.createProxyMiddleware({
    target: `http://localhost:${BACKEND_PORT}`,
    changeOrigin: true,
    ws: true,
    logLevel: 'info'
  });
  proxy(req, res, next);
});

// HTTP 서버 시작
const server = http.createServer(app);

server.listen(PROXY_PORT, () => {
  console.log(`✅ 프록시 서버 시작: http://${DOMAIN} -> http://localhost:${BACKEND_PORT}`);
  console.log(`   브라우저에서 http://${DOMAIN} 로 접근하세요.`);
  console.log(`   (sudo 권한이 필요할 수 있습니다)`);
});

server.on('error', (err) => {
  if (err.code === 'EACCES') {
    console.error('❌ 포트 80에 접근할 수 없습니다. sudo 권한이 필요합니다.');
    console.error('   또는 다른 포트를 사용하세요: PROXY_PORT=8080 node scripts/setup_simple_proxy.js');
  } else {
    console.error('❌ 서버 오류:', err);
  }
  process.exit(1);
});

