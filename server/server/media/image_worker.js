const path = require('path');
const fs = require('fs');

let sharp = null;
try {
    sharp = require('sharp');
} catch {}

exports.processImage = async ({ animal_id, srcPath }) => {
    if (!sharp) return { ok: false, reason: 'SHARP_NOT_INSTALLED' };
    
    const outDir = path.join(__dirname, '..', '..', 'data', 'artifacts', String(animal_id));
    fs.mkdirSync(outDir, { recursive: true });
    
    const out = path.join(outDir, `img_${Date.now()}.webp`);
    
    await sharp(srcPath)
        .resize({ width: 1080, height: 1920, fit: 'cover' })
        .modulate({ brightness: 1.05, saturation: 1.05 })
        .sharpen()
        .composite([{
            input: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="1920"><text x="40" y="1860" font-size="28" fill="white" opacity="0.7">PetLink Partners</text></svg>'),
            top: 0,
            left: 0
        }])
        .toFormat('webp', { quality: 86 })
        .toFile(out);
    
    return { ok: true, path: out };
};


