import { mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { SCREENSHOTS, SHOT_SIZE, SITE_META, shotSrc } from '../src/data/site.ts';

const WEBSITE_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC_DIR = path.resolve(WEBSITE_ROOT, '..', 'doc', 'screenshots');
const PUBLIC_DIR = path.join(WEBSITE_ROOT, 'public');
const OUT_DIR = path.join(PUBLIC_DIR, path.dirname(shotSrc('home'))); // 輸出路徑一律由 shotSrc 推出

// 實測 540x1200 q78：12 張約 370 KB，單張最大約 66 KB。
// 大小預算由 test/verify-dist.test.mjs 把關（唯一權威），這裡只印數字，方便調整品質
const WEBP_QUALITY = 78;

const SANS = "'Helvetica Neue', Arial, sans-serif";
const MONO = "'SF Mono', Menlo, Consolas, monospace";

const ICON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#4338CA"/>
  <circle cx="28" cy="28" r="13" fill="none" stroke="#FFFFFF" stroke-width="6"/>
  <path d="M38 38 L50 50" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round"/>
</svg>`;

const OG_SVG = `<svg width="1200" height="630" xmlns="http://www.w3.org/2000/svg">
  <rect width="1200" height="630" fill="#FAFAFA"/>
  <rect x="68" y="62" width="300" height="32" rx="16" fill="#4338CA"/>
  <text x="218" y="83" text-anchor="middle" font-family="${SANS}" font-size="14" font-weight="700" fill="#FFFFFF">OPEN SOURCE · MIT · FLUTTER</text>
  <text x="68" y="200" font-family="${MONO}" font-size="40" font-weight="700" fill="#111827">flutter_inspector_kit</text>
  <text x="68" y="280" font-family="${SANS}" font-size="30" font-weight="600" fill="#111827">Debug by following the chain,</text>
  <text x="68" y="322" font-family="${SANS}" font-size="30" font-weight="600" fill="#111827">not by poking points.</text>
  <text x="68" y="392" font-family="${SANS}" font-size="20" fill="#4B5563">Logs · Network · Navigator · Database — one timeline</text>
  <text x="68" y="540" font-family="${MONO}" font-size="18" fill="#4B5563">${SITE_META.baseUrl}</text>
</svg>`;

const shotPath = (id) => path.join(SRC_DIR, SCREENSHOTS[id]);

function buildRoundedMask(width, height, radius) {
  return Buffer.from(`<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
    <rect x="0" y="0" width="${width}" height="${height}" rx="${radius}" ry="${radius}" fill="#ffffff"/>
  </svg>`);
}

async function renderPhoneFrame(srcPath, width, height) {
  const innerW = width - 8;
  const innerH = height - 8;
  const screen = await sharp(srcPath)
    .resize(innerW, innerH, { fit: 'cover' })
    .ensureAlpha()
    .composite([{ input: buildRoundedMask(innerW, innerH, 16), blend: 'dest-in' }])
    .png()
    .toBuffer();
  const frame = `<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
    <rect x="0" y="0" width="${width}" height="${height}" rx="20" ry="20" fill="#1F2937" stroke="#4338CA" stroke-opacity="0.45" stroke-width="2"/>
  </svg>`;
  return sharp(Buffer.from(frame)).composite([{ input: screen, left: 4, top: 4 }]).png().toBuffer();
}

async function convertScreenshots() {
  await rm(OUT_DIR, { recursive: true, force: true }); // 先清空，避免改名後留下舊檔
  await mkdir(OUT_DIR, { recursive: true }); // recursive 會一併建立 public/
  let total = 0;
  for (const id of Object.keys(SCREENSHOTS)) {
    const info = await sharp(shotPath(id))
      .resize(SHOT_SIZE.width, SHOT_SIZE.height, { fit: 'cover' })
      .webp({ quality: WEBP_QUALITY, effort: 6 })
      .toFile(path.join(PUBLIC_DIR, shotSrc(id)));
    total += info.size;
    console.log(`${shotSrc(id)}: ${info.width}x${info.height}, ${info.size} B`);
  }
  console.log(`screenshots total: ${total} B`);
}

async function writeFavicon() {
  const info = await sharp(Buffer.from(ICON_SVG)).png().toFile(path.join(PUBLIC_DIR, SITE_META.faviconPath));
  console.log(`favicon.png: ${info.width}x${info.height}, ${info.size} B`);
}

async function writeOgCard() {
  const left = await renderPhoneFrame(shotPath('network'), 172, 372);
  const right = await renderPhoneFrame(shotPath('diagnostic-report'), 172, 372);
  const center = await renderPhoneFrame(shotPath('console'), 196, 426);
  const info = await sharp(Buffer.from(OG_SVG))
    .composite([
      { input: left, left: 650, top: 150 },
      { input: right, left: 974, top: 150 },
      { input: center, left: 800, top: 102 },
    ])
    .png({ compressionLevel: 9, palette: true, quality: 90, effort: 8 })
    .toFile(path.join(PUBLIC_DIR, SITE_META.ogImagePath));
  console.log(`og-card.png: ${info.width}x${info.height}, ${info.size} B`);
}

await convertScreenshots(); // 必須最先執行：它會建立 public/
await writeFavicon();
await writeOgCard();
