#!/usr/bin/env node
// 层② 性能测试驱动：Node.js 调用 wasm 对比（MoonBit wasm vs fast_qr-wasm32，S9c D18/D19）。
//
// 口径（对齐 bench.sh「多次取最小」）：
//   - fast_qr 侧：**Node 进程内** require wasm-bindgen 胶水后直调 `qr_with(content, ecl, version)`
//     循环 N 次（结果累加消费，防「调用被丢弃」）；`performance.now()` 包整循环，R 次取最小。
//   - MoonBit 侧：以 `moonrun`（~/.moon/bin/moonrun，原生 wasm 运行器）**子进程**跑 `cmd/bench`
//     `--target wasm` 产物（argv 指定点/N），同脚本同时钟计时，R 次取最小。表注写明两侧进程形态差异。
//     （Node 进程内 WASI 直调 bench.wasm 的 `__moonbit_fs_unstable` argv 注入 + stdout 捕获经 spike
//     验证不可靠，采用 S9c D18 降级路径；spike 结论见 docs/S9c-…-实现记录。）
//   - 逐位对齐：MoonBit `--dump <点>` vs fast_qr `qr_with` 各导出一份「QR_MATRIX」值全集 0/1 文本，
//     逐字符比对 + sha256（D19）。对齐只做一次、与计时正交。
//
// 用法:
//   node scripts/wasm-compare.mjs \
//     --fast <fast_qr.js 绝对路径> \
//     --moon <bench.wasm 绝对路径> \
//     [--moonrun <moonrun 路径>] [--reps 3] [--points V03,V10,V40] [--iters 2000,400,40]
//   （bash 包装见 scripts/bench-layer2.sh）

import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const require = createRequire(import.meta.url);

// ---- 参数解析 ----
function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const FAST_JS = arg('--fast', process.env.FAST_QR_PKG ? process.env.FAST_QR_PKG + '/fast_qr.js' : null);
const MOON_WASM = arg('--moon', process.env.MOON_BENCH_WASM || null);
const MOONRUN = arg('--moonrun', process.env.MOONRUN || 'moonrun');
const REPS = Number(arg('--reps', '3'));
const POINTS = (arg('--points', 'V03,V10,V40')).split(',').filter(Boolean);
const ITERS = Object.fromEntries((arg('--iters', '2000,400,40')).split(',').map((v, i) => [POINTS[i], Number(v)]));
if (!FAST_JS || !MOON_WASM) {
  console.error('usage: node wasm-compare.mjs --fast <fast_qr.js> --moon <bench.wasm> [--reps R]');
  process.exit(2);
}

const INPUT = 'https://example.com/';
const POINT_LABEL = { V03: 'V03H', V10: 'V10H', V40: 'V40H' };
const fast = require(FAST_JS);

// 逐字符 sha256
function sha256(s) { return createHash('sha256').update(s).digest('hex'); }

// fast_qr 枚举取值（wasm-bindgen 枚举按 Rust 变体名导出，如 ECL.H / Version.V03）
const ECL_H = fast.ECL.H;
const VER_OF = (pt) => fast.Version[pt];

// ---- MoonBit 侧（moonrun 子进程，execFileSync 捕获 stdout）----
function moonRun(args) {
  return execFileSync(MOONRUN, [MOON_WASM, ...args], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
}
function moonDump(pt) { return moonRun(['--dump', pt]); }

// ---- fast_qr 侧（Node 进程内调用）----
function fastRows(pt) {
  const m = fast.qr_with(INPUT, ECL_H, VER_OF(pt));
  if (!m || m.length === 0) throw new Error(`fast_qr qr_with(${pt}) returned empty`);
  const size = Math.round(Math.sqrt(m.length));
  const rows = [];
  for (let r = 0; r < size; r++) {
    let s = '';
    for (let c = 0; c < size; c++) s += m[r * size + c] ? '1' : '0';
    rows.push(s);
  }
  return rows;
}

// 规范 dump 文本：首行 QR_MATRIX <点名> size=<size>，随后 size 行 '0'/'1'
function canonicalText(label, rows) {
  return `QR_MATRIX ${label} size=${rows.length}\n${rows.join('\n')}\n`;
}

// 每点一次 build 的样本（对齐用，不参与计时）
function alignOne(pt) {
  const label = POINT_LABEL[pt];
  const fastRowsArr = fastRows(pt);
  // MoonBit --dump 输出即规范文本（末行 println 自带换行）；取其全文与 canonical 比较
  const moonText = moonDump(pt);
  const fastText = canonicalText(label, fastRowsArr);
  const same = moonText === fastText;
  return { label, same, moonSha: sha256(moonText), fastSha: sha256(fastText), fastRows: fastRowsArr.length };
}

// 计时：fast_qr 进程内 N 次调用（R 次取最小）
function timeFast(pt, n) {
  let best = Infinity;
  let cs = 0;
  for (let r = 0; r < REPS; r++) {
    let s = 0;
    const t0 = performance.now();
    for (let i = 0; i < n; i++) {
      const m = fast.qr_with(INPUT, ECL_H, VER_OF(pt));
      s += m.length; // 消费结果，防优化
    }
    const d = performance.now() - t0;
    cs = s;
    if (d < best) best = d;
  }
  return { bestMs: best, cs };
}

// 计时：MoonBit moonrun 子进程整程（R 次取最小）
function timeMoon(pt, n) {
  let best = Infinity;
  let cs = 0;
  for (let r = 0; r < REPS; r++) {
    const t0 = performance.now();
    const out = moonRun([pt, String(n)]);
    const d = performance.now() - t0;
    const m = /TOTAL_CHECKSUM=(\d+)/.exec(out);
    cs = m ? Number(m[1]) : NaN;
    if (d < best) best = d;
  }
  return { bestMs: best, cs };
}

// ---- 主体 ----
const alignResults = [];
console.log('# S9c 层② Node.js 调用 wasm 对比（input=https://example.com/, ecl=H, auto-mask, R=' + REPS + ' 取最小）');
console.log('> fast_qr 侧：Node 进程内直调 wasm-bindgen 产物 qr_with()；MoonBit 侧：moonrun 子进程整程（含进程启动）。');
console.log('');
console.log('| 基准点 | 迭代 N | 逐位对齐 | MoonBit wasm 最小(ms) | fast_qr-wasm32 最小(ms) | fast/moon | MoonBit checksum | fast checksum |');
console.log('|--------|-------:|---------|---------------------:|------------------------:|----------:|-----------------:|--------------:|');

const rows = [];
for (const pt of POINTS) {
  const n = ITERS[pt];
  const al = alignOne(pt);
  alignResults.push(al);
  const tm = timeMoon(pt, n);
  const tf = timeFast(pt, n);
  const ratio = tf.bestMs / tm.bestMs;
  rows.push({ pt, n, al, tm, tf, ratio });
  console.log(
    `| ${POINT_LABEL[pt]} | ${n} | ${al.same ? '✅ 一致' : '❌ 差异'} | ${tm.bestMs.toFixed(2)} | ${tf.bestMs.toFixed(2)} | ${ratio.toFixed(2)}x | ${tm.cs} | ${tf.cs} |`
  );
}

console.log('');
console.log('## 逐位对齐明细（sha256）');
let allSame = true;
for (const a of alignResults) {
  console.log(`- ${a.label}: ${a.same ? '一致' : '不一致'} (moon=${a.moonSha} / fast=${a.fastSha}) rows=${a.fastRows}`);
  if (!a.same) allSame = false;
}

if (!allSame) {
  console.error('\n❌ 逐位对齐存在差异，终止输出退出码 1。先核对参考检出版本/协议，勿改算法。');
  process.exit(1);
}
console.log('\n✅ 三基准点矩阵逐位对齐零差异（对齐 = S1-S7 快照对齐的跨宿主重确认）。');
