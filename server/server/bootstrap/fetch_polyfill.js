try {
  if (typeof globalThis.fetch !== 'function') {
    const { fetch, Headers, Request, Response } = require('undici');
    globalThis.fetch = fetch; globalThis.Headers = Headers;
    globalThis.Request = Request; globalThis.Response = Response;
    console.log('fetch polyfilled by undici');
  }
} catch (e) { console.warn('undici polyfill skipped', e && e.message); }
