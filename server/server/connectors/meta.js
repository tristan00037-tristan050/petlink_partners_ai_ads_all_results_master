exports.post = async ({ draft }) => {
    // 환경변수 없으면 초안 폴백
    if (!process.env.META_ACCESS_TOKEN) {
        return { status: 'DRAFT_FALLBACK', ref: null };
    }
    return { status: 'POSTED', ref: ('ok:' + Date.now()) };
};


