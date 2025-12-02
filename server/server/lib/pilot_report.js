const fetchFn = (global.fetch || require("undici").fetch || globalThis.fetch);

module.exports = {
  async generate() {
    const port = process.env.PORT || "5902";
    const h = { "X-Admin-Key": process.env.ADMIN_KEY || "" };
    
    // r8.9에서 마련한 /admin/reports/pilot.json 사용 (없으면 기본 구조 반환)
    try {
      const res = await fetchFn(`http://localhost:${port}/admin/reports/pilot.json`, { headers: h });
      if (!res.ok) throw new Error("pilot_json_nonok");
      const j = await res.json();
      return {
        ok: true,
        pilot: j.pilot || { go: false },
        metrics: j.metrics || { payments: {}, session_gate: {} },
        thresholds: j.thresholds || {},
        ts: new Date().toISOString()
      };
    } catch (e) {
      // pilot.json이 없으면 기본 구조 반환
      const sessionGate = await (async () => {
        try {
          const sgRes = await fetchFn(`http://localhost:${port}/admin/metrics/session/gate`, { headers: h });
          if (sgRes.ok) {
            const sg = await sgRes.json();
            return sg.gate || { pass: false, rate: 0, p95_ms: 0 };
          }
        } catch {}
        return { pass: false, rate: 0, p95_ms: 0 };
      })();
      
      return {
        ok: true,
        pilot: { go: sessionGate.pass },
        metrics: {
          payments: { success_rate: 0, dlq_rate: 0 },
          session_gate: sessionGate
        },
        thresholds: {
          pay_success: parseFloat(process.env.PILOT_SLO_PAY_SUCCESS || "0.95"),
          dlq_rate: parseFloat(process.env.PILOT_SLO_DLQ_RATE || "0.01"),
          session_req: process.env.PILOT_SLO_SESSION_REQ === "true"
        },
        ts: new Date().toISOString()
      };
    }
  }
};
