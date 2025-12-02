const { request } = require('undici');

async function callPolicyAI(text) {
  const endpoint = process.env.POLICY_AI_ENDPOINT;
  const apiKey   = process.env.POLICY_AI_API_KEY;
  const timeout  = parseInt(process.env.POLICY_AI_TIMEOUT_MS || '1200', 10);

  if (!endpoint) return { ok: false, score: null, reason: 'no_endpoint' };

  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeout);

  try {
    const { body, statusCode } = await request(endpoint, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...(apiKey ? { authorization: `Bearer ${apiKey}` } : {})
      },
      body: JSON.stringify({ text }),
      signal: controller.signal
    });
    clearTimeout(id);
    if (statusCode !== 200) return { ok: false, score: null, reason: `http_${statusCode}` };
    const data = await body.json();
    // 기대 스키마: { score: 0~1, labels?: [...], reasons?: [...] }
    return { ok: true, score: typeof data.score === 'number' ? data.score : null, raw: data };
  } catch (e) {
    clearTimeout(id);
    return { ok: false, score: null, reason: 'timeout_or_network' };
  }
}

module.exports = { callPolicyAI };

