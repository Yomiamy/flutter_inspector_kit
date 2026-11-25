import assert from 'node:assert/strict';
import test from 'node:test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

import { SCREENSHOTS, SHOT_SIZE, shotSrc } from '../src/data/site.ts';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SRC_DIR = path.join(ROOT, '..', 'doc', 'screenshots');

// 同一張圖 q78 WebP 實測最多 0.20% 像素差距 >64；換成別張最少 3.66%。
// 不比 bytes：不同平台的編碼器輸出不保證逐位元相同，位元比對會讓 CI 偶發失敗
const MAX_BAD_PIXEL_RATIO = 0.005;
const BAD_CHANNEL_DIFF = 64;

const pixels = (file) =>
  sharp(file).resize(SHOT_SIZE.width, SHOT_SIZE.height, { fit: 'cover' }).removeAlpha().raw().toBuffer();

const badPixelRatio = (a, b) => {
  let bad = 0;
  for (let i = 0; i < a.length; i += 3) {
    if ([0, 1, 2].some((c) => Math.abs(a[i + c] - b[i + c]) > BAD_CHANNEL_DIFF)) bad++;
  }
  return bad / (a.length / 3);
};

test('public/screenshots 沒有落後 doc/screenshots 來源 PNG', async () => {
  for (const id of Object.keys(SCREENSHOTS)) {
    const [src, out] = await Promise.all([
      pixels(path.join(SRC_DIR, SCREENSHOTS[id])),
      pixels(path.join(ROOT, 'public', shotSrc(id))),
    ]);
    const ratio = badPixelRatio(src, out);
    assert.ok(ratio <= MAX_BAD_PIXEL_RATIO, `${id} 與來源 PNG 差異 ${(ratio * 100).toFixed(2)}%：先跑 npm run prepare:assets`);
  }
});
