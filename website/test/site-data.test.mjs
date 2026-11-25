import assert from 'node:assert/strict';
import test from 'node:test';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { INSTALL, LOCALES, SCREENSHOTS, SITE_DATA, SITE_META, shotSrc } from '../src/data/site.ts';

const PUBLIC_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'public');
const inPublic = (webPath) => existsSync(path.join(PUBLIC_DIR, webPath));

// 文案的形狀：字串一律記成 'string'，陣列保留長度，id 保留原值。兩語系的形狀必須相同
const shape = (v, key) =>
  key === 'id'
    ? v
    : typeof v === 'string'
      ? 'string'
      : Array.isArray(v)
        ? v.map((x) => shape(x))
        : Object.fromEntries(Object.keys(v).sort().map((k) => [k, shape(v[k], k)]));

const strings = (v) => (typeof v === 'string' ? [v] : Object.values(v).flatMap(strings));
const shotsOf = (d) => [d.hero.shot, ...d.sections.flatMap((s) => s.shots)];

test('兩語系齊全且結構一致', () => {
  assert.deepEqual(Object.keys(SITE_DATA).sort(), [...LOCALES].sort());
  assert.deepEqual(shape(SITE_DATA['zh-tw']), shape(SITE_DATA.en));
});

test('12 張截圖每張恰用一次、都有 alt，且已輸出到 public/', () => {
  const all = Object.keys(SCREENSHOTS).sort();
  assert.equal(all.length, 12);
  for (const locale of LOCALES) {
    const shots = shotsOf(SITE_DATA[locale]);
    assert.deepEqual(shots.map((s) => s.id).sort(), all, `${locale} 截圖清單與 SCREENSHOTS 不符`);
    for (const s of shots) assert.ok(s.alt.trim().length > 0, `${locale} ${s.id} 缺 alt`);
  }
  for (const id of all) {
    assert.ok(inPublic(shotSrc(id)), `缺 public${shotSrc(id)}：先跑 npm run prepare:assets`);
  }
  assert.ok(inPublic(SITE_META.faviconPath), '缺 favicon');
  assert.ok(inPublic(SITE_META.ogImagePath), '缺 og-card');
});

test('外部連結一律 https', () => {
  // 任何 scheme:xxx 都納入檢查（含 javascript:、mailto:），不能只挑 xxx:// 的
  const urls = [...strings(SITE_META), ...strings(SITE_DATA)].filter((s) => /^[a-z][a-z0-9+.-]*:\S/i.test(s));
  assert.ok(urls.length >= 6);
  for (const u of urls) assert.match(u, /^https:\/\//, u);
});

test('文案不含版本號與 Markdown 反引號', () => {
  for (const s of strings(SITE_DATA)) {
    assert.doesNotMatch(s, /\d+\.\d+\.\d+/, `疑似寫死版本號：${s}`);
    assert.doesNotMatch(s, /`/, `Markdown 反引號外洩到文案：${s}`);
  }
  assert.doesNotMatch(INSTALL.addCommand + INSTALL.initSnippet, /\d+\.\d+\.\d+/);
});
