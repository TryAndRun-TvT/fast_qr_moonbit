#!/usr/bin/env node
// S9q 宿主调用面**统计稳定性**探针：回答 ISSUE #50 的「是否存在统计差异 / 是否应当多次运行取平均值」。
//
// 【为什么单独一个脚本，而不塞进 host-bench.mjs】
//   `host-bench.mjs` 回答「多快」（点估计）；本脚本回答「这个点估计可信到几位」（区间估计）。
//   两者口径必须同源（同一产物、同一 INPUT、同一 VER_SEL、同 R 取最小），否则区间盖不住点估计。
//   本脚本**不改动**既有基线脚本行为，只做重抽样与离散度报告，供文档引用。
//
// 【方法：轮次级重抽样（round-level resampling）】
//   在**同一 Node 进程**内，把「一次 R 轮取最小」当作一个样本，独立重复 `--rounds` 次，
//   于是得到 `--rounds` 个互相独立的点估计 → 直接量出：
//     ① 轮间分布（mean / median / 极差 / σ / CV）；
//     ② 比值 fast/ours 的配对分布（这才是对外引用的量）；
//     ③ 「只跑一次（R=1）」的失稳率 = 单轮估值偏离真值多少；
//     ④ 轮內离散（同一次 run 内 R 个样本的 spread）；
//     ⑤ lag-1 自相关 r1：判别噪声是白噪声（r1≈0）还是热/频漂移（r1→1）。
//
// 【已知结论摘要（详见 docs/S9q）】CV 随单次成本下降而急剧上升（V40H ≈0.3% → V03H ≈3.6%）；
//   V03H 的 r1≈0.68 说明是漂移不是白噪声；故「多跑几轮」的边际收益低于「跨进程重抽样」。
//
// 用法:
//   node scripts/bench-host-var.mjs --moon-gc <host-probe.wasm> [--fast <fast_qr.js>] \
//        [--rounds 15] [--reps 5] [--iters 2000,400,40]
//   （bash 包装见 scripts/bench-host-var.sh）

import fs from 'node:fs';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

// ---- 参数解析 ----
function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const MOON_GC_WASM = arg('--moon-gc', process.env.MOON_GC_HOST_PROBE_WASM || null);
const FAST_JS = arg('--fast', process.env.FAST_QR_PKG ? process.env.FAST_QR_PKG + '/fast_qr.js' : null);
const ROUNDS = Number(arg('--rounds', '15'));
const REPS = Number(arg('--reps', '5'));
const POINTS = (arg('--points', 'V03,V10,V40')).split(',').filter(Boolean);
const ITERS = Object.fromEntries(
  (arg('--iters', '2000,400,40')).split(',').map((v, i) => [POINTS[i], Number(v)]),
);
if (!MOON_GC_WASM) {
  console.error('usage: node bench-host-var.mjs --moon-gc <host-probe.wasm> [--fast <fast_qr.js>] [--rounds 15] [--reps 5]');
  process.exit(2);
}

const INPUT = 'https://example.com/';
const POINT_LABEL = { V03: 'V03H', V10: 'V10H', V40: 'V40H' };
const VER_SEL = { V03: 0, V10: 1, V40: 2 };

// ---- 统计辅助（与 host-bench.mjs 同实现：中位数为主口径）----
const mean = (a) => a.reduce((s, x) => s + x, 0) / a.length;
const median = (a) => {
  const s = [...a].sort((x, y) => x - y);
  const h = s.length >> 1;
  return s.length % 2 ? s[h] : (s[h - 1] + s[h]) / 2;
};
const std = (a) => {
  const m = mean(a);
  return Math.sqrt(mean(a.map((x) => (x - m) ** 2)));
};
const cv = (a) => (mean(a) === 0 ? NaN : std(a) / mean(a));
const spread = (a) => ((Math.max(...a) - Math.min(...a)) / median(a)) * 100; // %
/// lag-1 自相关：白噪声 ≈0；单调漂移 → 1。用于区分「量测噪声」与「热/频漂移」。
function lag1(a) {
  const m = mean(a);
  const d = a.map((x) => x - m);
  let num = 0;
  let den = 0;
  for (let i = 0; i < d.length - 1; i++) num += d[i] * d[i + 1];
  for (let i = 0; i < d.length; i++) den += d[i] * d[i];
  return den === 0 ? NaN : num / den;
}

// ---- MoonBit wasm-gc 宿主装载（与 host-bench.mjs 同一路径）----
async function loadMoonGc(file) {
  const src = fs.readFileSync(file);
  const raw = new WebAssembly.Module(src);
  const extra = {};
  const stringConstants = [];
  for (const i of WebAssembly.Module.imports(raw)) {
    if (i.module === 'spectest') continue;
    if (i.module.startsWith('wasm:')) continue;
    (extra[i.module] ||= {})[i.name] = i.name;
    stringConstants.push(`${i.module}.${i.name}`);
  }
  const mod = await WebAssembly.compile(src, { builtins: ['js-string'] });
  const inst = await WebAssembly.instantiate(mod, {
    spectest: { print_char: () => {} },
    ...extra,
  });
  if (typeof inst.exports.qr_generate !== 'function') {
    throw new Error('host-probe 未导出 qr_generate（需 pkgtype(kind:"foreign_library") + link.exports）');
  }
  return { exports: inst.exports, stringConstants };
}

const gc = await loadMoonGc(MOON_GC_WASM);
let fast = null;
if (FAST_JS) fast = require(FAST_JS);

// ---- 一轮 = 一次 host-bench.mjs 口径（R 轮取最小）；返回本轮全部 R 个单轮样本 ----
function roundOurs(pt) {
  const sel = VER_SEL[pt];
  const n = ITERS[pt];
  let acc = gc.exports.qr_generate(INPUT, sel); // 热机（不计）
  const per = [];
  for (let r = 0; r < REPS; r++) {
    acc = 0;
    const t0 = performance.now();
    for (let i = 0; i < n; i++) acc = gc.exports.qr_generate(INPUT, sel);
    per.push((performance.now() - t0) / n);
  }
  if (acc === 0) throw new Error('dead code');
  return per;
}
function roundFast(pt) {
  if (!fast) return null;
  const n = ITERS[pt];
  const ECL_H = fast.ECL.H;
  const ver = fast.Version[pt];
  let s = fast.qr_with(INPUT, ECL_H, ver).length; // 热机
  const per = [];
  for (let r = 0; r < REPS; r++) {
    s = 0;
    const t0 = performance.now();
    for (let i = 0; i < n; i++) s += fast.qr_with(INPUT, ECL_H, ver).length;
    per.push((performance.now() - t0) / n);
  }
  if (s === 0) throw new Error('dead code');
  return per;
}

console.log('# S9q 宿主调用面统计稳定性（同一 Node 进程内，轮次级重抽样）');
console.log('');
console.log(`> 一轮 = 独立跑 ${REPS} 次取最小（= 一次 \`host-bench.mjs\` 的口径）；重复 ${ROUNDS} 轮 → ${ROUNDS} 个独立样本。`);
console.log(`> 宿主：${process.version}；输入 \`${INPUT}\`（20B）；N=${JSON.stringify(ITERS)}；R=1 口径的离散来自同一轮内的 ${REPS} 个原始样本。`);
console.log(`> \`_\` 命名空间字符串常量导入：${gc.stringConstants.length} 条。`);
console.log('');

const data = {};
for (const pt of POINTS) {
  const oursBest = [];
  const oursR1 = [];
  const fastBest = [];
  const fastR1 = [];
  for (let k = 0; k < ROUNDS; k++) {
    const ro = roundOurs(pt);
    oursBest.push(Math.min(...ro));
    oursR1.push(spread(ro));
    const rf = roundFast(pt);
    if (rf) {
      fastBest.push(Math.min(...rf));
      fastR1.push(spread(rf));
    }
  }
  data[pt] = { oursBest, oursR1, fastBest, fastR1 };
}

console.log('## 1. 各口径的轮间分布（ms/次，一轮 = 独立 R 轮取最小）');
console.log('| 点 | 侧 | mean | median | min | max | 极差 | σ | CV | lag-1 r1 |');
console.log('|----|----|-----:|-------:|----:|----:|-----:|---:|---:|---------:|');
function distRow(pt, side, a) {
  console.log(
    `| ${POINT_LABEL[pt]} | ${side} | ${mean(a).toFixed(4)} | ${median(a).toFixed(4)} | ${Math.min(...a).toFixed(4)} | ${Math.max(...a).toFixed(4)} | ${((Math.max(...a) / Math.min(...a) - 1) * 100).toFixed(1)}% | ${std(a).toFixed(4)} | ${(cv(a) * 100).toFixed(2)}% | ${lag1(a).toFixed(2)} |`,
  );
}
for (const pt of POINTS) {
  distRow(pt, 'ours（宿主面）', data[pt].oursBest);
  if (data[pt].fastBest.length) distRow(pt, 'fast_qr', data[pt].fastBest);
}

console.log('');
console.log('## 2. 比值 fast/ours 的轮间分布（同轮配对 —— 这是对外引用的量）');
console.log('| 点 | mean | median | min | max | 配对范围 | σ | CV | 最坏单轮 vs 均值 |');
console.log('|----|-----:|-------:|----:|----:|---------:|---:|---:|-----------------:|');
for (const pt of POINTS) {
  if (!data[pt].fastBest.length) continue;
  const r = data[pt].oursBest.map((m, i) => data[pt].fastBest[i] / m);
  const dev = (x) => (x / mean(r) - 1) * 100;
  console.log(
    `| ${POINT_LABEL[pt]} | ${mean(r).toFixed(3)} | ${median(r).toFixed(3)} | ${Math.min(...r).toFixed(3)} | ${Math.max(...r).toFixed(3)} | ±${((Math.max(...r) - Math.min(...r)) / mean(r) * 100).toFixed(1)}% | ${std(r).toFixed(4)} | ${(cv(r) * 100).toFixed(2)}% | ${dev(Math.min(...r)).toFixed(1)}% ~ +${dev(Math.max(...r)).toFixed(1)}% |`,
  );
}

console.log('');
console.log('## 3. 「只跑一轮（R=1 单次 run）」的失稳率 = 单轮估值偏离本批真值');
console.log('| 点 | 侧 | 最大偏高 | 最大偏低 | 典型偏差 σ |');
console.log('|----|----|--------:|--------:|----------:|');
for (const pt of POINTS) {
  for (const [side, a] of [['ours', data[pt].oursBest], ['fast_qr', data[pt].fastBest]]) {
    if (!a.length) continue;
    const t = mean(a);
    const d = a.map((x) => (x / t - 1) * 100);
    console.log(
      `| ${POINT_LABEL[pt]} | ${side} | +${Math.max(...d).toFixed(1)}% | ${Math.min(...d).toFixed(1)}% | ${std(d).toFixed(2)}% |`,
    );
  }
}

console.log('');
console.log('## 4. 轮內离散（同一次 run 内 R 个原始样本的 (max−min)/中位数）');
console.log('| 点 | ours 中位 | ours 最大 | fast_qr 中位 | fast_qr 最大 |');
console.log('|----|---------:|---------:|-------------:|-------------:|');
for (const pt of POINTS) {
  const f = data[pt].fastR1.length ? data[pt].fastR1 : [NaN];
  console.log(
    `| ${POINT_LABEL[pt]} | ${median(data[pt].oursR1).toFixed(1)}% | ${Math.max(...data[pt].oursR1).toFixed(1)}% | ${f.length && !Number.isNaN(f[0]) ? median(f).toFixed(1) + '%' : 'n/a'} | ${f.length && !Number.isNaN(f[0]) ? Math.max(...f).toFixed(1) + '%' : 'n/a'} |`,
  );
}

console.log('');
console.log('## 5. 结论口径（脚本自动给出，避免手工摘数）');
const cvOf = {};
for (const pt of POINTS) if (data[pt].fastBest.length) {
  const r = data[pt].oursBest.map((m, i) => data[pt].fastBest[i] / m);
  cvOf[pt] = cv(r) * 100;
}
for (const pt of POINTS) {
  if (cvOf[pt] === undefined) continue;
  const need = cvOf[pt] <= 0.5 ? 'R≥3 已足' : cvOf[pt] <= 1.5 ? 'R≥5 建议' : 'R≥7 且应跨进程重抽样';
  console.log(
    `- ${POINT_LABEL[pt]}：比值 CV = ${cvOf[pt].toFixed(2)}%、r1 = ${lag1(data[pt].oursBest).toFixed(2)} → ${need}；`,
  );
}
console.log('- 报告纪律：对外引用**必须给「同 run 内成对比值 + 离散」**；绝对毫秒只可在同一 run 内相比。');
console.log('- 探针自检：任一点 CV > 10% 或 ROUNDS < 5 视为样本不足，请增大 --rounds 后再引用。');
const bad = POINTS.some((pt) => cvOf[pt] !== undefined && cvOf[pt] > 10);
if (ROUNDS < 5 || bad) {
  console.error('\n❌ 样本不足（ROUNDS<5 或 CV>10%）；不要引用本批数字。');
  process.exit(1);
}
console.log('\n✅ 统计稳定性探针完成。');
