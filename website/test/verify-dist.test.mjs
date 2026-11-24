import assert from 'node:assert/strict';
import test from 'node:test';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { INSTALL, LOCALES, SCREENSHOTS, SITE_DATA, SITE_META, shotSrc } from '../src/data/site.ts';

const DIST = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'dist');
// 截圖與 og-card 的大小預算只在這裡檢查（唯一權威）；prepare-assets 只印數字
const MAX_SHOT_BYTES = 153_600; // 150 KB
const MAX_SHOTS_TOTAL_BYTES = 614_400; // 600 KB
const MAX_OG_BYTES = 460_800; // 450 KB

assert.ok(existsSync(DIST), 'website/dist/ 不存在：先跑 npm run build');

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const distPath = (webPath) => path.join(DIST, webPath.endsWith('/') ? `${webPath}index.html` : webPath);
const SHOT_PATHS = Object.keys(SCREENSHOTS).map(shotSrc);
const pages = LOCALES.map((locale) => ({
  locale,
  d: SITE_DATA[locale],
  html: readFileSync(distPath(SITE_DATA[locale].path), 'utf8'),
}));

test('每頁的 lang、canonical、hreflang、og:image 正確', () => {
  for (const { d, html } of pages) {
    assert.match(html, new RegExp(`<html[^>]+lang="${esc(d.htmlLang)}"`));
    assert.match(html, new RegExp(`<link[^>]+rel="canonical"[^>]+href="${esc(SITE_META.baseUrl + d.path)}"`));
    for (const other of LOCALES.map((l) => SITE_DATA[l])) {
      assert.match(
        html,
        new RegExp(`<link[^>]+hreflang="${esc(other.htmlLang)}"[^>]+href="${esc(SITE_META.baseUrl + other.path)}"`),
      );
    }
    assert.match(
      html,
      new RegExp(`<meta[^>]+property="og:image"[^>]+content="${esc(SITE_META.baseUrl + SITE_META.ogImagePath)}"`),
    );
  }
});

test('安裝指令在頁面上，且沒有寫死版本號', () => {
  for (const { locale, html } of pages) {
    assert.ok(html.includes(INSTALL.addCommand), `${locale} 缺安裝指令`);
    assert.doesNotMatch(html, /flutter_inspector_kit:\s*\^?\d/, `${locale} 出現寫死的版本約束`);
  }
});

test('站內連結、錨點、截圖引用與 img alt 都成立', () => {
  for (const { locale, html } of pages) {
    for (const [, ref] of html.matchAll(/(?:href|src)="(\/[^"#]*)"/g)) {
      assert.ok(existsSync(distPath(ref)), `${locale}: ${ref} 不存在於 dist/`);
    }
    const ids = new Set(Array.from(html.matchAll(/\bid="([^"]+)"/g), (m) => m[1]));
    for (const [, anchor] of html.matchAll(/href="#([^"]+)"/g)) {
      assert.ok(ids.has(anchor), `${locale}: 錨點 #${anchor} 沒有對應的 id`);
    }
    for (const shot of SHOT_PATHS) {
      assert.ok(html.includes(shot), `${locale}: 沒有引用 ${shot}`);
    }
    for (const [tag] of html.matchAll(/<img\b[^>]*>/g)) {
      assert.match(tag, /\salt="/, `${locale}: <img> 缺 alt：${tag}`);
    }
  }
});

test('dist 的截圖目錄恰好是 12 張 WebP 且在預算內；og-card 在預算內', () => {
  const dir = path.join(DIST, path.dirname(SHOT_PATHS[0]));
  const names = readdirSync(dir).sort();
  assert.deepEqual(names, SHOT_PATHS.map((p) => path.basename(p)).sort());
  let total = 0;
  for (const name of names) {
    const buf = readFileSync(path.join(dir, name));
    assert.equal(buf.subarray(0, 4).toString('ascii'), 'RIFF', name);
    assert.equal(buf.subarray(8, 12).toString('ascii'), 'WEBP', name);
    assert.ok(buf.byteLength <= MAX_SHOT_BYTES, `${name} ${buf.byteLength} B 超過 150 KB`);
    total += buf.byteLength;
  }
  assert.ok(total <= MAX_SHOTS_TOTAL_BYTES, `截圖總計 ${total} B 超過 600 KB`);
  assert.ok(statSync(distPath(SITE_META.ogImagePath)).size <= MAX_OG_BYTES, 'og-card.png 超過 450 KB');
});
