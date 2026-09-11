#!/usr/bin/env node
// S9e 层② 性能对比驱动（**历史口径**）：**统一 Node 进程内**调用两侧 wasm（MoonBit `wasm`/WASI vs fast_qr-wasm32）。
//
// 【口径状态（S9j，2026-09-11）】本驱动用的 MoonBit 侧是 `wasm`(WASI) **兼容兜底后端**，
//   与 `moon.mod` 的 `preferred_target = "wasm-gc"`（实际分发形态）不一致，**不再作为对外引用口径**。
//   层② 默认口径见 scripts/gc-compare.mjs（`wasm-gc` vs fast_qr，同一 Node 进程）。
//   本驱动保留用于复现 S9e 历史记录：`MOON_TARGET=wasm bash scripts/bench-layer2.sh`。
//
// 为什么统一（对齐 issue「并非统一通过 nodejs 调用」）：
//   S9c 旧口径是「fast_qr 侧 Node 进程内直调 + MoonBit 侧 moonrun 子进程整程」——两侧不同宿主形态，
//   MoonBit 侧被额外计入一个**进程启动固定开销**（实测占整程 12–20%），对比数字被系统性放大。
//   本驱动把 MoonBit 侧改为「同一 Node 进程内实例化 + 调用」（scripts/moonbit-wasm-runner.mjs），
//   使两侧共享同一进程、同一 `performance.now()` 时钟、同一 N 次循环形态。
//
// 计时口径（对齐 bench.sh「多次取最小」）：
//   - 两侧都做 **N 次「一次 build」**，`performance.now()` 包住整循环，R 次取最小。
//   - MoonBit 侧：每次迭代新建一个 wasm Instance（`_start` 只能跑一次，moonrun 亦然）后调用
//     `cmd/bench <点> 1`（N=1 的一次 build）。宿主 shim 模块级预热编译，不含编译开销。
//   - fast_qr 侧：Node 进程内循环调 `qr_with(content, ecl, version)`，结果累加消费。
//   - 由此两侧都**不含**进程启动，也都不含「N 次 build」之外的额外放大；单次均摊 = 最小循环时间 / N。
//
// 逐位对齐：MoonBit `--dump <点>`（一次 build 导值全集）vs fast_qr `qr_with` 规范文本，逐字符 + sha256。
//   对齐与计时正交，每次只做一次。
//
// 用法:
//   node scripts/wasm-compare.mjs \
//     --fast <fast_qr.js 绝对路径> \
//     --moon <bench.wasm 绝对路径> \
//     [--reps 3] [--points V03,V10,V40] [--iters 2000,400,40] [--selfcheck-n 40]
//   （bash 包装见 scripts/bench-layer2.sh）

import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { loadMoonWasm } from './moonbit-wasm-runner.mjs';

const require = createRequire(import.meta.url);

// ---- 参数解析 ----
function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const FAST_JS = arg('--fast', process.env.FAST_QR_PKG ? process.env.FAST_QR_PKG + '/fast_qr.js' : null);
const MOON_WASM = arg('--moon', process.env.MOON_BENCH_WASM || null);
const REPS = Number(arg('--reps', '3'));
// --moonrun 仅用于「跨宿主一致性抽检」（同源产物在 moonrun 下应为同一结果），不参与计时。
const MOONRUN = arg('--moonrun', process.env.MOONRUN || 'moonrun');
const POINTS = (arg('--points', 'V03,V10,V40')).split(',').filter(Boolean);
const ITERS = Object.fromEntries((arg('--iters', '2000,400,40')).split(',').map((v, i) => [POINTS[i], Number(v)]));
if (!FAST_JS || !MOON_WASM) {
  console.error('usage: node wasm-compare.mjs --fast <fast_qr.js> --moon <bench.wasm> [--reps R]');
  process.exit(2);
}

const INPUT = 'https://example.com/';
const POINT_LABEL = { V03: 'V03H', V10: 'V10H', V40: 'V40H' };
const fast = require(FAST_JS);
const moon = loadMoonWasm(MOON_WASM); // 预热编译一次，run() 可复用

function sha256(s) {
  return createHash('sha256').update(s).digest('hex');
}

const ECL_H = fast.ECL.H;
const VER_OF = (pt) => fast.Version[pt];

// ---- 逐位对齐（每点一次 build，与计时正交）----
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
function canonicalText(label, rows) {
  return `QR_MATRIX ${label} size=${rows.length}\n${rows.join('\n')}\n`;
}
function moonDump(pt) {
  const r = moon.run(['--dump', pt]);
  if (r.exitCode !== 0) throw new Error(`MoonBit --dump ${pt} failed: ${r.stdout}`);
  return r.stdout;
}
function alignOne(pt) {
  const label = POINT_LABEL[pt];
  const fastText = canonicalText(label, fastRows(pt));
  const moonText = moonDump(pt);
  return {
    label,
    same: moonText === fastText,
    moonSha: sha256(moonText),
    fastSha: sha256(fastText),
    fastRows: fastRows(pt).length,
  };
}

// ---- 计时：MoonBit（Node 进程内）----
// 两种口径都报，避免任何一侧因宿主成本被误读：
//  (A) 逐次调用（与 fast_qr 侧「一次 qr_with = 一次调用」严格同形）：
//      每次迭代新建 Instance（`_start` 只能跑一次，moonrun 亦然）后跑 `cmd/bench <点> 1`。
//      此口径含「Node 托管 wasm 的 Instance 创建 + WASI/argv 初始化」固定成本（实测 ~0.08ms/次）。
//  (B) 单实例摊薄（纯 build 边际成本）：一个 Instance 内跑 `cmd/bench <点> N`（N 次 build 一次 _start），
//      剔掉 Instance 创建固定项，用于与 fast_qr 的每模块系数做同口径比较。
function timeMoonPerCall(pt, n, reps) {
  let best = Infinity;
  let lastOut = '';
  for (let r = 0; r < reps; r++) {
    const t0 = performance.now();
    for (let i = 0; i < n; i++) lastOut = moon.run([pt, '1']).stdout;
    const d = performance.now() - t0;
    if (d < best) best = d;
  }
  const m = /TOTAL_CHECKSUM=(\d+)/.exec(lastOut);
  return { bestMs: best, cs: m ? Number(m[1]) : NaN };
}
function timeMoonAmortized(pt, n, reps) {
  let best = Infinity;
  let lastOut = '';
  for (let r = 0; r < reps; r++) {
    const t0 = performance.now();
    lastOut = moon.run([pt, String(n)]).stdout;
    const d = performance.now() - t0;
    if (d < best) best = d;
  }
  const m = /TOTAL_CHECKSUM=(\d+)/.exec(lastOut);
  return { bestMs: best, cs: m ? Number(m[1]) : NaN };
}

// ---- 计时：fast_qr（Node 进程内直调）----
function timeFast(pt, n, reps) {
  let best = Infinity;
  let cs = 0;
  for (let r = 0; r < reps; r++) {
    let s = 0;
    const t0 = performance.now();
    for (let i = 0; i < n; i++) {
      const m = fast.qr_with(INPUT, ECL_H, VER_OF(pt));
      s += m.length; // 消费结果，防「调用被丢弃」
    }
    const d = performance.now() - t0;
    cs = s;
    if (d < best) best = d;
  }
  return { bestMs: best, cs };
}

// ---- 跨宿主抽检：同源产物在 moonrun 下应给出同一 dump（对齐一次性确认）----
function moonrunDump(pt) {
  try {
    return execFileSync(MOONRUN, [MOON_WASM, '--dump', pt], {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch {
    return null;
  }
}

// ---- 主体 ----
console.log('# S9e 层② Node 进程内统一调用对比（input=https://example.com/, ecl=H, auto-mask, R=' + REPS + ' 取最小）');
console.log('> 两侧**同一 Node 进程**调用：MoonBit = scripts/moonbit-wasm-runner.mjs 进程内实例化 + 调 cmd/bench；');
console.log('> fast_qr = require wasm-bindgen 胶水后直调 qr_with()。两侧均不含子进程启动。');
console.log('');
console.log('| 基准点 | 迭代 N | 对齐 | MoonBit 单次(A) ms | MoonBit 单次(B) ms | fast_qr 单次 ms | fast/moon(A) | fast/moon(B) |');
console.log('|--------|-------:|:----:|------------------:|------------------:|---------------:|-------------:|-------------:|');

const rows = [];
for (const pt of POINTS) {
  const n = ITERS[pt];
  const al = alignOne(pt);
  const tm = timeMoonPerCall(pt, n, REPS);
  const tma = timeMoonAmortized(pt, n, REPS);
  const tf = timeFast(pt, n, REPS);
  const ratio = tf.bestMs / tm.bestMs;
  const ratioA = tf.bestMs / tma.bestMs;
  rows.push({ pt, n, al, tm, tma, tf, ratio, ratioA });
  console.log(
    `| ${POINT_LABEL[pt]} | ${n} | ${al.same ? '✅' : '❌'} | ${(tm.bestMs / n).toFixed(4)} | ${(tma.bestMs / n).toFixed(4)} | ${(tf.bestMs / n).toFixed(4)} | ${ratio.toFixed(3)}x | ${ratioA.toFixed(3)}x |`
  );
}

console.log('');
console.log('## 逐位对齐明细（sha256）');
let allSame = true;
for (const a of rows) {
  const al = a.al;
  const mr = moonrunDump(a.pt);
  const crossHost = mr === null ? '（moonrun 抽检不可用）' : mr === moonDump(a.pt) ? '、且与 moonrun 同结果' : '、⚠️ 与 moonrun 结果不一致';
  console.log(`- ${al.label}: ${al.same ? '一致' : '不一致'} (moon=${al.moonSha} / fast=${al.fastSha}) rows=${al.fastRows}${crossHost}`);
  if (!al.same) allSame = false;
}

if (!allSame) {
  console.error('\n❌ 逐位对齐存在差异，终止输出退出码 1。先核对参考检出版本/协议，勿改算法。');
  process.exit(1);
}
console.log('\n✅ 三基准点矩阵逐位对齐零差异（对齐 = S1-S7 快照对齐的跨宿主重确认）。');
