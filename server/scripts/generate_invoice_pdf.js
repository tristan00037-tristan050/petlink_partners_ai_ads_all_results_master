#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Puppeteer를 사용한 PDF 생성 (옵션)
// 실제로는 puppeteer가 설치되어 있어야 함

const args = process.argv.slice(2);
const htmlPath = args.find(arg => arg.startsWith('--html='))?.split('=')[1];
const outPath = args.find(arg => arg.startsWith('--out='))?.split('=')[1];

if (!htmlPath || !outPath) {
    console.error('Usage: node generate_invoice_pdf.js --html=web/invoice.html --out=out/invoice_YYYYMM.pdf');
    process.exit(1);
}

// 출력 디렉토리 생성
const outDir = path.dirname(outPath);
if (!fs.existsSync(outDir)) {
    fs.mkdirSync(outDir, { recursive: true });
}

console.log(`HTML 파일: ${htmlPath}`);
console.log(`출력 경로: ${outPath}`);

// Puppeteer를 사용한 PDF 생성 (설치되어 있는 경우)
try {
    const puppeteer = require('puppeteer');
    
    (async () => {
        const browser = await puppeteer.launch();
        const page = await browser.newPage();
        
        const htmlContent = fs.readFileSync(htmlPath, 'utf8');
        await page.setContent(htmlContent, { waitUntil: 'networkidle0' });
        
        await page.pdf({
            path: outPath,
            format: 'A4',
            printBackground: true
        });
        
        await browser.close();
        console.log(`PDF 생성 완료: ${outPath}`);
    })();
} catch (error) {
    console.warn('Puppeteer가 설치되어 있지 않습니다. 브라우저에서 직접 인쇄하세요.');
    console.warn('설치: npm install puppeteer');
    console.log(`HTML 파일을 브라우저에서 열어 PDF로 저장하세요: ${htmlPath}`);
}


