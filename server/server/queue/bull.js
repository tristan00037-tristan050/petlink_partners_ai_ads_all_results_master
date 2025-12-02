let BullMQ = null;
try {
    BullMQ = require('bullmq');
} catch {}

const image = require('../media/image_worker');
const video = require('../media/video_worker');

const REDIS_URL = process.env.REDIS_URL || 'redis://127.0.0.1:6379';

const queues = { image: null, video: null };

function ensureQueues() {
    if (!BullMQ) return;
    
    const conn = { connection: { url: REDIS_URL } };
    
    queues.image = queues.image || new BullMQ.Queue('media:image', conn);
    queues.video = queues.video || new BullMQ.Queue('media:video', conn);
    
    if (!queues._imageWorker) {
        queues._imageWorker = new BullMQ.Worker('media:image', async (j) => image.processImage(j.data), { ...conn });
    }
    
    if (!queues._videoWorker) {
        queues._videoWorker = new BullMQ.Worker('media:video', async (j) => video.processVideo(j.data), { ...conn });
    }
}

module.exports = { queues, ensureQueues };


