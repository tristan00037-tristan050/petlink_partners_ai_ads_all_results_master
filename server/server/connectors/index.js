const meta = require('./meta');
const tiktok = require('./tiktok');
const youtube = require('./youtube');
const kakao = require('./kakao');
const naver = require('./naver');

const crypto = require('crypto');
const SIGN = process.env.APP_HMAC || 'dev-secret';

const sleep = ms => new Promise(r => setTimeout(r, ms));

const sign = (obj) => {
    const p = Buffer.from(JSON.stringify(obj)).toString('base64url');
    const mac = crypto.createHmac('sha256', SIGN).update(p).digest('base64url');
    return p + "." + mac;
};

async function tryPost(fn, payload, attempts = 3) {
    let err = null;
    for (let i = 0; i < attempts; i++) {
        try {
            return await fn(payload);
        } catch (e) {
            err = e;
            await sleep(400 * Math.pow(2, i));
        }
    }
    throw err || new Error('POST_FAILED');
}

exports.routePostings = async ({ draft, channels }) => {
    const results = [];
    
    for (const ch of channels) {
        try {
            let res;
            if (ch === 'META') res = await tryPost(meta.post, { draft });
            else if (ch === 'TIKTOK') res = await tryPost(tiktok.post, { draft });
            else if (ch === 'YOUTUBE') res = await tryPost(youtube.post, { draft });
            else if (ch === 'KAKAO') res = await tryPost(kakao.post, { draft });
            else if (ch === 'NAVER') res = await tryPost(naver.post, { draft });
            else throw new Error('UNKNOWN_CHANNEL');
            
            results.push({
                channel: ch,
                status: res.status,
                approve_token: null,
                ref: res.ref || null
            });
        } catch (e) {
            const approve_token = sign({ ch, draft_id: draft.id, exp: Date.now() + 15 * 60 * 1000 });
            results.push({
                channel: ch,
                status: 'DRAFT_FALLBACK',
                approve_token,
                reason: String(e.message || e)
            });
        }
    }
    
    return results;
};


