#!/usr/bin/env node
// S10 附录 D 落地：**独立第三方解码回读**审计（jsqr）。
//
// 为什么需要它：本仓库所有断言都是「与 fast_qr 逐位一致」。一旦两侧同时理解错规范，
//   就会同时错且测不出。本脚本用**第三方纯 JS 解码器**把矩阵像素化后解码，
//   断言读回原文 == 输入——这是「符合 QR 规范语义」的独立证据（跨实现、不共享代码）。
//
// 口径与标定（实测，S10 附录 D）：
//   - 矩阵来源：MoonBit 侧经 `moonrun <bench.wasm> --dump <点>`（0/1 行主序规范矩阵）；
//   - 像素化：每模块 scale=4 像素、静默区 4 模块（**不要用 scale=1**：小版本会假红灯）；
//   - 负向证据：`--mutate` 会把矩阵内环翻转，断言「解码失败或读回不同」——证明脚本能红。
//
// 依赖：node + `jsqr`（纯 JS，零原生依赖）。**仅本地/审计，不入 push CI**（依赖治理见 S10 T3-c）。
//
// 用法:
//   node scripts/qr-decode-check.mjs --moon-gc <bench.wasm> [--moonrun <path>]
//        [--expr "https://example.com/"] [--points V03,V10,V40] [--scale 4] [--margin 4] [--mutate]
//   node scripts/qr-decode-check.mjs --moon-gc <bench.wasm> --corpus   # T3-d 全语料（54 组，含 auto 靶点）
//   （bash 包装见 scripts/test-audit.sh decode）

// `--corpus`（T3-d）：走 `cmd/bench --dump-case <i>` 的 **54 组多内容语料**
//   （三模式 × 4 ECL × {V01,V05,V10,V40} = 48 组 grid + 6 组 `version=None` 自动版本靶点），
//   逐组断言 jsQR 读回原文 == 期望内容（按模式构造）。
//   为什么这批语料不可省：它是 **v5 `select_capacity` 模式语义 bug 的唯一可复现证据**——
//   旧实现在 `version=None` 时按 Numeric 预算选版本，Byte/Alnum 长输入被写进装不下它的
//   数据区（实测 4 组 auto 语料解码返回 NULL）。

import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const arg = (n, d) => {
  const i = process.argv.indexOf(n);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : d;
};
const has = (n) => process.argv.includes(n);

const MOON_GC = arg('--moon-gc', '');
const MOONRUN = arg('--moonrun', process.env.MOONRUN || 'moonrun');
const EXPR = arg('--expr', 'https://example.com/');
const POINTS = arg('--points', 'V03,V10,V40').split(',').map((x) => x.trim()).filter(Boolean);
const SCALE = Number(arg('--scale', '4'));
const MARGIN = Number(arg('--margin', '4'));
const MUTATE = has('--mutate');
const CORPUS = has('--corpus');

if (!MOON_GC) {
  console.error('用法: node scripts/qr-decode-check.mjs --moon-gc <bench.wasm> [--moonrun <path>]');
  process.exit(2);
}
let jsQR;
try {
  jsQR = (await import('jsqr')).default;
} catch {
  console.error('!! 未安装 jsqr（本地审计依赖）：npm i jsqr');
  process.exit(2);
}

// MoonBit 侧矩阵：`cmd/bench --dump <点>` 输出 `QR_MATRIX <label> size=<n>` + n 行 0/1。
function dumpMatrix(point) {
  const out = execFileSync(MOONRUN, [MOON_GC, '--dump', point], {
    encoding: 'utf8',
    maxBuffer: 1 << 28,
  });
  const lines = out.trimEnd().split('\n');
  if (!lines[0].startsWith('QR_MATRIX')) throw new Error(`--dump ${point} 输出异常: ${lines[0]}`);
  const rows = lines.slice(1);
  const size = Number(/size=(\d+)/.exec(lines[0])[1]);
  if (rows.length !== size) throw new Error(`${point} 行数 ${rows.length} != size ${size}`);
  return rows;
}

// 像素化：每模块 SCALE 像素、四周 MARGIN 模块的**白色静默区**（QR 规范要求 ≥4）。
function toRGBA(rows, scale, margin) {
  const n = rows.length;
  const S = (n + 2 * margin) * scale;
  const data = new Uint8ClampedArray(S * S * 4);
  for (let i = 0; i < data.length; i += 4) {
    data[i] = data[i + 1] = data[i + 2] = 255;
    data[i + 3] = 255;
  }
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      if (rows[y][x] !== '1') continue;
      for (let dy = 0; dy < scale; dy++) {
        for (let dx = 0; dx < scale; dx++) {
          const px = ((y + margin) * scale + dy) * S + (x + margin) * scale + dx;
          data[px * 4] = data[px * 4 + 1] = data[px * 4 + 2] = 0;
        }
      }
    }
  }
  return { data, size: S };
}

function decode(rows, scale, margin) {
  const { data, size } = toRGBA(rows, scale, margin);
  return jsQR(data, size, size);
}

// 负向证据：在**左上 finder 图案内环**（模块 (1..3,1..3)）整体反向——定位图案破坏后
// 解码器应无法定位/读出。**实测教训**：单格数据翻转（哪怕多处）都会被 RS 纠错完全掩盖，
// 必须破坏定位图案才能得到「能红」的负向证据（见 S10 附录 D）。
function mutate(rows) {
  const out = rows.map((r) => r.split(''));
  for (let y = 1; y <= 3; y++) {
    for (let x = 1; x <= 3; x++) {
      out[y][x] = out[y][x] === '1' ? '0' : '1';
    }
  }
  return out.map((r) => r.join(''));
}

// ── T3-d 全语料模式 ────────────────────────────────────────────────────────
if (CORPUS) {
  const listOut = execFileSync(MOONRUN, [MOON_GC, '--dump-case', 'list'], {
    encoding: 'utf8', maxBuffer: 1 << 28,
  });
  const cases = listOut.trimEnd().split('\n').filter((l) => l.startsWith('QR_CASE_LIST'))
    .map((l) => {
      const g = (k) => new RegExp(`${k}=([^ ]+)`).exec(l)[1];
      return { index: Number(g('index')), kind: g('kind'), mode: g('mode'),
        ecl: g('ecl'), version: g('version'), content_len: Number(g('content_len')) };
    });
  console.log(`# 独立解码回读审计（jsqr）—— T3-d 全语料（${cases.length} 组）`);
  console.log(`> MoonBit 侧 = ${MOON_GC}；像素化 scale=${SCALE}、margin=${MARGIN}\n`);
  let cbad = 0;
  for (const c of cases) {
    const out = execFileSync(MOONRUN, [MOON_GC, '--dump-case', String(c.index)], {
      encoding: 'utf8', maxBuffer: 1 << 28,
    }).trimEnd().split('\n');
    const li = out.findIndex((l) => l.startsWith('QR_MATRIX'));
    if (li < 0) { console.log(`❌ case ${c.index} 无 QR_MATRIX`); cbad++; continue; }
    const size = Number(/size=(\d+)/.exec(out[li])[1]);
    const rows = out.slice(li + 1, li + 1 + size);
    if (rows.length !== size) { console.log(`❌ case ${c.index} 行数不符`); cbad++; continue; }
    let r = null;
    try { r = decode(rows, SCALE, MARGIN); } catch (e) {
      console.log(`⚠️ case ${c.index} jsQR 抛异常：${e.message}`); cbad++; continue;
    }
    const pad = c.mode === 'Numeric' ? '9' : c.mode === 'Alphanumeric' ? 'A' : 'z';
    const want = pad.repeat(c.content_len);
    const ok = Boolean(r) && r.data === want;
    if (!ok) {
      cbad++;
      console.log(`❌ case ${c.index} ${c.kind} ${c.mode}/${c.ecl}/${c.version} ` +
        `读回 ${r ? JSON.stringify(r.data).slice(0, 40) + `(len=${r.data.length})` : 'NULL'}，` +
        `期望 ${c.content_len} 个 '${pad}'`);
    }
  }
  if (cbad > 0) {
    console.error(`\n❌ T3-d 语料 ${cbad}/${cases.length} 组未达预期，退出码 1。`);
    process.exit(1);
  }
  console.log(`\n✅ T3-d 语料 ${cases.length}/${cases.length} 组第三方解码读回原文一致。`);
  process.exit(0);
}

console.log(`# 独立解码回读审计（jsqr）\n> 输入 ${JSON.stringify(EXPR)}；MoonBit 侧 = ${MOON_GC}`);
console.log(`> 像素化 scale=${SCALE}（每模块像素）、margin=${MARGIN}（静默区模块）；` +
  `${MUTATE ? '**负向模式**（矩阵已被植入翻转）' : '正向模式'}\n`);

let bad = 0;
for (const pt of POINTS) {
  const rows = dumpMatrix(pt);
  const mutated = MUTATE ? mutate(rows) : null;
  const r = decode(mutated ?? rows, SCALE, MARGIN);
  const got = r ? r.data : null;
  if (!MUTATE) {
    const ok = got === EXPR;
    if (!ok) bad++;
    console.log(`${ok ? '✅' : '❌'} ${pt}（${rows.length}×${rows.length} 模块）读回 ` +
      `${got === null ? 'NULL' : JSON.stringify(got)}${ok ? '' : `，期望 ${JSON.stringify(EXPR)}`}`);
  } else {
    // 负向：期望「解码失败」或「读回与原文不同」。若仍读回原文，说明植入不足以被检出（脚本能力弱）。
    const caught = got !== EXPR;
    if (!caught) bad++;
    console.log(`${caught ? '✅' : '⚠️'} ${pt} 负向对照：读回 ` +
      `${got === null ? 'NULL（解码失败，已检出）' : JSON.stringify(got)}` +
      `${caught ? '' : ' —— 与原文相同，说明该植入未被第三方解码器检出（需加强植入）'}`);
  }
}

if (bad > 0) {
  console.error(`\n❌ ${bad} 项未达预期，退出码 1。`);
  process.exit(1);
}
console.log(`\n✅ ${POINTS.length} 点全部达到预期${MUTATE ? '（负向对照有效）' : '（独立第三方解码读回原文一致）'}。`);
