const { spawnSync, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

function hasFfmpeg() {
    const { spawnSync } = require('child_process');
    const p = spawnSync('ffmpeg', ['-version'], { stdio: 'ignore' });
    return p.status === 0;
}

exports.processVideo = async ({ animal_id, srcPath, durationSec = 15 }) => {
    if (!hasFfmpeg()) return { ok: false, reason: 'FFMPEG_NOT_FOUND' };
    
    const outDir = path.join(__dirname, '..', '..', 'data', 'artifacts', String(animal_id));
    fs.mkdirSync(outDir, { recursive: true });
    
    const out = path.join(outDir, `vid_${Date.now()}.mp4`);
    const thumb = path.join(outDir, `thumb_${Date.now()}.jpg`);
    
    const args = [
        '-y', '-i', srcPath,
        '-vf', 'scale=1080:-2,setsar=1,crop=1080:1920,eq=brightness=0.02:contrast=1.05',
        '-t', String(Math.max(12, Math.min(18, durationSec))),
        '-c:v', 'libx264', '-preset', 'fast', '-crf', '23',
        '-c:a', 'aac', '-shortest',
        out
    ];
    
    await new Promise((res, rej) => {
        const p = spawn('ffmpeg', args);
        p.on('close', c => c === 0 ? res() : rej(new Error('FFMPEG_FAIL')));
    });
    
    await new Promise((res, rej) => {
        const p = spawn('ffmpeg', ['-y', '-i', out, '-ss', '00:00:01.000', '-vframes', '1', thumb]);
        p.on('close', c => c === 0 ? res() : rej(new Error('THUMB_FAIL')));
    });
    
    return { ok: true, video: out, thumb };
};

