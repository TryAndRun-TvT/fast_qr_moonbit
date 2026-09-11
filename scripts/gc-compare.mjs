#!/usr/bin/env node
// S9j 层② **默认口径**性能对比驱动：统一 Node 进程内调用 **MoonBit wasm-gc** vs **fast_qr-wasm32**。
//
// 【口径状态（S9j，2026-09-11）】本驱动是层②**对外引用口径**（MoonBit 侧 = `wasm-gc`，即
//   `moon.mod` 的 `preferred_target`、实际分发形态）。S9e 的 `wasm`(WASI) 对比为**历史口径**，
//   保留在 scripts/wasm-compare.mjs（`MOON_TARGET=wasm bash scripts/bench-layer2.sh` 复现）。
//
// 为什么单开 gc 通道（口径收敛，避免歧义）：
//   S9e 把两侧计时统一到了「同一 Node 进程内」，但 MoonBit 侧用的是 `wasm`(WASI) 兼容后端产物——
//   而 `moon.mod` 的 `preferred_target = "wasm-gc"`（`wasm` 仅是宿主兼容兜底）。
//   对外引用性能时，「MoonBit 是哪个后端」与「比的是哪个产物」两处歧义随之而来。
//   本驱动把层②的 MoonBit 侧换成**实际分发形态 `wasm-gc`**，与 fast_qr 在**同一 Node 进程**内对撞。
//
// 为什么以前没做：wasm-gc 产物需 WasmGC + `spectest.print_char` + `__moonbit_fs_unstable`（argv）宿主面，
//   早先 Node 端不可直接加载；现 Node v24(V8) 已可编译运行 wasm-gc 产物（实测），
//   本驱动提供最小 shim（协议照 `moonbitlang/core` 的 `env/env_wasm.mbt` 实现，非猜测）。
//
// 计时口径（与 S9e 严格同形，两侧同一进程、同一 performance.now()、同一 N 次循环、R 次取最小）：
//   (A) 逐次调用：每次迭代新建 Instance 后跑 `cmd/bench <点> 1`（`_start` 每次只跑一次），
//       含 Node 托管 Instance 创建的固定项（与 fast_qr「一次调用」同形的保守口径）。
//   (B) 单实例摊薄：一个 Instance 内一次 `_start` 跑 `cmd/bench <点> N`，剔除 Instance 固定项，
//       即**纯 build 边际成本**，为对外引用的主口径。
//
// 正确性护栏（缺一即退出码 1）：
//   1) 逐位对齐：MoonBit(wasm-gc) `--dump <点>` 文本 vs fast_qr `qr_with` 规范矩阵，逐字符 + sha256；
//   2) 跨宿主一致：Node shim 下的 `--dump` 输出 vs `moonrun <wasm-gc bench>` 输出逐字节一致；
//   3) checksum 互证（可选 `--moon-wasm`）：gc 与 `wasm` 后端同点 checksum 一致（跨后端同源码）。
//
// 用法:
//   node scripts/gc-compare.mjs \
//     --fast <fast_qr.js 绝对路径> \
//     --moon-gc <bench.wasm (wasm-gc) 绝对路径> \
//     [--moon-wasm <bench.wasm (wasm) 绝对路径>] \
//     [--reps 3] [--points V03,V10,V40] [--iters 2000,400,40] \
//     [--moonrun <moonrun 路径>]
//   （bash 包装见 scripts/bench-layer2.sh）

import fs from 'node:fs';
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
const MOON_GC_WASM = arg('--moon-gc', process.env.MOON_GC_BENCH_WASM || null);
const MOON_WASM = arg('--moon-wasm', process.env.MOON_BENCH_WASM || null);
const MOONRUN = arg('--moonrun', process.env.MOONRUN || 'moonrun');
const REPS = Number(arg('--reps', '3'));
const POINTS = (arg('--points', 'V03,V10,V40')).split(',').filter(Boolean);
const ITERS = Object.fromEntries(
  (arg('--iters', '2000,400,40')).split(',').map((v, i) => [POINTS[i], Number(v)])
);
if (!FAST_JS || !MOON_GC_WASM) {
  console.error('usage: node gc-compare.mjs --fast <fast_qr.js> --moon-gc <bench.wasm> [--moon-wasm <bench.wasm>]');
  process.exit(2);
}

const INPUT = 'https://example.com/';
const POINT_LABEL = { V03: 'V03H', V10: 'V10H', V40: 'V40H' };

// ---- MoonBit wasm-gc 宿主 shim ----
// 协议来源：`moonbitlang/core` 的 `env/env_wasm.mbt`（`#external` 绑定）——
//   args_get() -> XExternStringArray（不透明句柄，guest 只透传）
//   begin_read_string_array(sa) -> handle；string_array_read_string(handle) -> XExternString；
//   begin_read_string(e) -> handle；string_read_char(handle) -> 码点（-1 = 结束）；finish_read_string(handle)
//   数组以哨兵字符串 `ffi_end_of_/string_array` 结束（与 moonrun 同约定）。
// 句柄用宿主侧自增整数 + Map 承载，不涉及 guest 内存。
const END_OF_STRING_ARRAY = 'ffi_end_of_/string_array';

class GcBenchHost {
  constructor(file) {
    this.buf = fs.readFileSync(file);
    this.mod = new WebAssembly.Module(this.buf); // 预热编译一次（不含在计时内）
  }
  /// 跑一次 `_start`（新建 Instance，与 moonrun / wasm 侧 runner 同形），返回 stdout。
  run(argv) {
    const strings = ['bench', ...argv, END_OF_STRING_ARRAY];
    let out = '';
    let next = 1;
    const table = new Map();
    const H = (o) => {
      const h = next++;
      table.set(h, o);
      return h;
    };
    const imports = {
      spectest: {
        print_char: (c) => {
          out += String.fromCodePoint(c);
        },
      },
      __moonbit_fs_unstable: {
        args_get: () => H(strings),
        begin_read_string_array: (sa) => H({ arr: table.get(sa), i: 0 }),
        string_array_read_string: (h) => {
          const st = table.get(h);
          return H(st.arr[st.i++] ?? END_OF_STRING_ARRAY);
        },
        begin_read_string: (s) => H({ s: table.get(s), i: 0 }),
        string_read_char: (h) => {
          const st = table.get(h);
          // 以码点推进（与 moonrun 的 codepoint 语义一致）；-1 表示结束。
          return st.i < st.s.length ? st.s.codePointAt(st.i++) : -1;
        },
        finish_read_string: (h) => table.delete(h),
        finish_read_string_array: (h) => table.delete(h),
      },
    };
    const inst = new WebAssembly.Instance(this.mod, imports);
    inst.exports._start();
    return out;
  }
}

const gc = new GcBenchHost(MOON_GC_WASM);
const fast = require(FAST_JS);
const ECL_H = fast.ECL.H;
const VER_OF = (pt) => fast.Version[pt];
const sha256 = (s) => createHash('sha256').update(s).digest('hex');

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
function gcDump(pt) {
  const out = gc.run(['--dump', pt]);
  if (!out.startsWith('QR_MATRIX')) throw new Error(`wasm-gc --dump ${pt} failed: ${JSON.stringify(out)}`);
  return out;
}
function alignOne(pt) {
  const label = POINT_LABEL[pt];
  const fastText = canonicalText(label, fastRows(pt));
  const moonText = gcDump(pt);
  return { label, same: moonText === fastText, moonSha: sha256(moonText), fastSha: sha256(fastText), rows: fastRows(pt).length };
}

// ---- 计时：MoonBit（wasm-gc，Node 进程内）----
function timeGcPerCall(pt, n, reps) {
  let best = Infinity;
  let cs = NaN;
  for (let r = 0; r < reps; r++) {
    const t0 = performance.now();
    let last = '';
    for (let i = 0; i < n; i++) last = gc.run([pt, '1']);
    const d = performance.now() - t0;
    const m = /TOTAL_CHECKSUM=(\d+)/.exec(last);
    cs = m ? Number(m[1]) : NaN;
    if (d < best) best = d;
  }
  return { bestMs: best, cs };
}
function timeGcAmortized(pt, n, reps) {
  let best = Infinity;
  let cs = NaN;
  for (let r = 0; r < reps; r++) {
    const t0 = performance.now();
    const out = gc.run([pt, String(n)]);
    const d = performance.now() - t0;
    const m = /TOTAL_CHECKSUM=(\d+)/.exec(out);
    cs = m ? Number(m[1]) : NaN;
    if (d < best) best = d;
  }
  return { bestMs: best, cs };
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

// ---- 跨宿主抽检：同源 wasm-gc 产物在 moonrun 下应给出同一 dump ----
function moonrunDump(pt) {
  try {
    return execFileSync(MOONRUN, [MOON_GC_WASM, '--dump', pt], {
      encoding: 'utf8',
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch {
    return null;
  }
}

// ---- 可选：跨后端 checksum 互证（gc vs wasm，同源码）----
function wasmBackendChecksum(pt, n) {
  if (!MOON_WASM || !fs.existsSync(MOON_WASM)) return null;
  try {
    const mod = loadMoonWasm(MOON_WASM);
    const out = mod.run([pt, String(n)]).stdout;
    const m = /TOTAL_CHECKSUM=(\d+)/.exec(out);
    return m ? Number(m[1]) : null;
  } catch {
    return null;
  }
}

// ---- 主体 ----
console.log('# S9j 层② 统一 Node 进程内对比：**MoonBit wasm-gc（默认后端）vs fast_qr-wasm32**');
console.log('> 两侧同一 Node 进程、同一 `performance.now()` 时钟、同一 N 次循环、R=' + REPS + ' 取最小。');
console.log('> MoonBit 侧 = wasm-gc 产物 + 最小宿主 shim（`spectest.print_char` + `__moonbit_fs_unstable` argv，');
console.log('> 协议照 `moonbitlang/core` `env/env_wasm.mbt` 实现）；fast_qr 侧 = wasm-bindgen 胶水直调 `qr_with`。');
console.log('> 输出口径：`wasm`(WASI) 侧数字不再参与本对比（历史口径见 S9e，避免「比的是哪个后端」歧义）。');
console.log('');

console.log('| 基准点 | 迭代 N | 对齐 | MoonBit(wasm-gc) 单次(A) ms | MoonBit(wasm-gc) 单次(B) ms | fast_qr 单次 ms | fast/ours(A) | fast/ours(B) |');
console.log('|--------|-------:|:----:|---------------------------:|---------------------------:|---------------:|-------------:|-------------:|');

const rows = [];
let allSame = true;
let allHostSame = true;
let allChecksumSame = true;
for (const pt of POINTS) {
  const n = ITERS[pt];
  const al = alignOne(pt);
  const ta = timeGcPerCall(pt, n, REPS);
  const tb = timeGcAmortized(pt, n, REPS);
  const tf = timeFast(pt, n, REPS);
  // 护栏：Node shim vs moonrun（跨宿主一致）
  const mr = moonrunDump(pt);
  const hostSame = mr === null ? null : mr === gcDump(pt);
  // 护栏：gc checksum vs wasm 后端 checksum（跨后端一致）
  const csWasm = wasmBackendChecksum(pt, n);
  const csSame = csWasm === null ? null : csWasm === tb.cs;
  rows.push({ pt, n, al, ta, tb, tf, hostSame, csSame });
  if (!al.same) allSame = false;
  if (hostSame === false) allHostSame = false;
  if (csSame === false) allChecksumSame = false;
  const ratioA = tf.bestMs / ta.bestMs;
  const ratioB = tf.bestMs / tb.bestMs;
  console.log(
    `| ${POINT_LABEL[pt]} | ${n} | ${al.same ? '✅' : '❌'} | ${(ta.bestMs / n).toFixed(4)} | ${(tb.bestMs / n).toFixed(4)} | ${(tf.bestMs / n).toFixed(4)} | ${ratioA.toFixed(3)}x | ${ratioB.toFixed(3)}x |`
  );
}

console.log('');
console.log('## 逐位对齐明细（sha256）');
for (const a of rows) {
  const host = a.hostSame === null ? '（moonrun 抽检不可用）' : a.hostSame ? '、且与 moonrun 同结果' : '、⚠️ 与 moonrun 结果不一致';
  const cs = a.csSame === null ? '' : a.csSame ? '、checksum 与 `wasm` 后端一致' : '、⚠️ checksum 与 `wasm` 后端不一致';
  console.log(`- ${a.al.label}: ${a.al.same ? '一致' : '不一致'} (moon-gc=${a.al.moonSha} / fast=${a.al.fastSha}) rows=${a.al.rows}${host}${cs}`);
}

if (!allSame) {
  console.error('\n❌ 逐位对齐存在差异，终止输出退出码 1。先核对参考检出版本/协议，勿改算法。');
  process.exit(1);
}
if (!allHostSame) {
  console.error('\n❌ Node shim 与 moonrun 输出不一致，终止输出退出码 1。');
  process.exit(1);
}
if (!allChecksumSame) {
  console.error('\n❌ wasm-gc 与 wasm 后端 checksum 不一致，终止输出退出码 1。');
  process.exit(1);
}
console.log('\n✅ 三基准点矩阵逐位对齐零差异；Node shim / moonrun 跨宿主一致；双后端 checksum 互证一致。');
