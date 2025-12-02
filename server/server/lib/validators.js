const { z } = require('zod');

const prefsSchema = z.object({
    ig_enabled: z.boolean().optional(),
    tt_enabled: z.boolean().optional(),
    yt_enabled: z.boolean().optional(),
    kakao_enabled: z.boolean().optional(),
    naver_enabled: z.boolean().optional(),
});

const radiusSchema = z.object({
    radius_km: z.number().min(1).max(20)
});

const weightsSchema = z.object({
    mon: z.number().positive().optional(),
    tue: z.number().positive().optional(),
    wed: z.number().positive().optional(),
    thu: z.number().positive().optional(),
    fri: z.number().positive().optional(),
    sat: z.number().positive().optional(),
    sun: z.number().positive().optional(),
    holiday: z.number().positive().optional(),
    holidays: z.array(z.string()).optional()
});

const pacerPreviewSchema = z.object({
    store_id: z.number().positive(),
    month: z.string().regex(/^\d{4}-\d{2}$/),
    remaining_budget: z.number().nonnegative(),
    band_pct: z.number().min(0).max(100).optional()
});

const pacerApplySchema = z.object({
    store_id: z.number().positive(),
    month: z.string().regex(/^\d{4}-\d{2}$/),
    schedule: z.array(z.object({
        date: z.string(),
        amount: z.number(),
        min: z.number(),
        max: z.number()
    }))
});

const animalSchema = z.object({
    store_id: z.number().positive(),
    species: z.string(),
    breed: z.string().optional(),
    sex: z.string().optional(),
    age_label: z.string().optional(),
    title: z.string().optional(),
    caption: z.string().optional(),
    note: z.string().optional()
});

const draftSchema = z.object({
    store_id: z.number().positive(),
    animal_id: z.number().optional(),
    channels: z.array(z.enum(['META', 'TIKTOK', 'YOUTUBE', 'KAKAO', 'NAVER'])).optional().default([]),
    copy: z.string().optional().default('')
});

const ingestSchema = z.array(z.object({
    ts: z.string(),
    store_id: z.number().optional(),
    channel: z.string().optional(),
    placement: z.string().optional(),
    impressions: z.number().nonnegative().optional().default(0),
    views: z.number().nonnegative().optional().default(0),
    clicks: z.number().nonnegative().optional().default(0),
    cost: z.number().nonnegative().optional().default(0),
    conversions: z.object({
        dm: z.number().optional(),
        call: z.number().optional(),
        route: z.number().optional(),
        lead: z.number().optional()
    }).optional().default({})
}));

module.exports = {
    prefsSchema,
    radiusSchema,
    weightsSchema,
    pacerPreviewSchema,
    pacerApplySchema,
    animalSchema,
    draftSchema,
    ingestSchema
};


