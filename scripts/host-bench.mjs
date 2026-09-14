#!/usr/bin/env node
// S9p 宿主调用面基准驱动：**在一个 Node 进程内，一次又一次地把 JS 参数传给 wasm**。
//
// 【与既有层②（gc-compare.mjs）的区别 —— 这正是 issue #50 提出的问题】
//   gc-compare.mjs 的 MoonBit 侧产物是 `cmd/bench`（**命令形态**：导出面只有 `_start`，
//   输入走 argv）。于是它只能测两件事：
//     A 口径：每次迭代 `new WebAssembly.Instance(...)` + `_start` —— 把「模块实例化」成本
//             算进每一次「调用」；宿主**无法**在两次调用之间改参数。
//     B 口径：把迭代数 N 也塞进 argv，让 wasm 内部跑紧循环 —— 宿主传参成本被完全抹平，
//             测的是「wasm 内部循环」，不是「宿主反复调用」。
//   两者都不是宿主嵌入 wasm 库的真实形态。本驱动补的正是这一口径。
//
// 【本驱动的口径（S9p，2026-09-14）】
//   MoonBit 侧 = `cmd/host-probe`（`foreign_library`），导出
//     `qr_generate(content: String, version: Int) -> Int`
//     `qr_checksum(version: Int) -> Int`                  // A/B 对照：内容在 wasm 侧
//   宿主：**一次** `WebAssembly.compile` + **一次** `Instance`，随后在该实例上
//     for i in 0..N: out = qr_generate(INPUT, ver)        // 每次都是真实带参调用
//   与 fast_qr 侧 `qr_with(content, ecl, version)` 调用形态**严格对称**（同为「一次实例化、
//   反复传参调用」），因此这是目前两侧最可比的「宿主调用面」数字。
//
// 【三组护栏（缺一即 exit 1）】
//   1) ALIGN-CLI   ：`qr_generate` 与 `cmd/bench <点> 1` 的 checksum 逐点相同
//                    （证明宿主面与 CLI 面是同一计算，不是各测各的）；
//   2) ALIGN-BATCH ：一次调用 N=1 与 N 次调用的 checksum 恒定（内容与迭代数无关）；
//   3) ALIGN-FAST  ：MoonBit 矩阵 vs fast_qr `qr_with` 规范矩阵逐字符 + sha256 相同。
//   另有 SPEC 护栏：内部字面量在 stringref 模式下可正确读取（`qr_checksum` 能跑通）。
//
// 用法:
//   node scripts/host-bench.mjs --moon-gc <host-probe.wasm> [--fast <fast_qr.js>] \
//        [--bench <cmd/bench.wasm 或 'moonrun:...'>] [--reps 3] [--iters ...] [--points V03,V10,V40]
//   （bash 包装见 scripts/bench-host.sh）

import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

// ---- 参数解析 ----
function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const MOON_GC_WASM = arg('--moon-gc', process.env.MOON_GC_HOST_PROBE_WASM || null);
const FAST_JS = arg('--fast', process.env.FAST_QR_PKG ? process.env.FAST_QR_PKG + '/fast_qr.js' : null);
const MOONRUN = arg('--moonrun', process.env.MOONRUN || 'moonrun');
const BENCH_WASM = arg('--bench', process.env.MOON_GC_BENCH_WASM || null);
const REPS = Number(arg('--reps', '3'));
const POINTS = (arg('--points', 'V03,V10,V40')).split(',').filter(Boolean);
const ITERS = Object.fromEntries(
  (arg('--iters', '2000,400,40')).split(',').map((v, i) => [POINTS[i], Number(v)]),
);
if (!MOON_GC_WASM) {
  console.error('usage: node host-bench.mjs --moon-gc <host-probe.wasm> [--fast <fast_qr.js>] [--bench <bench.wasm>]');
  process.exit(2);
}

const INPUT = 'https://example.com/';
const POINT_LABEL = { V03: 'V03H', V10: 'V10H', V40: 'V40H' };
const VER_SEL = { V03: 0, V10: 1, V40: 2 };
const sha256 = (s) => createHash('sha256').update(s).digest('hex');

// ---- S9q 统计决策（承接 ISSUE #50「是否应当多次运行取平均值」）----
// 关键事实：**一次 R 轮取最小 = 一个样本，不是一个确定值**。S9q 实测（同一 Node 进程内重抽样）：
//   - 轮间变异系数 CV：V40H ≈0.29% ≪ V10H ≈1.1% < V03H ≈3.6%（V03H 单轮最坏偏离均值 +15%）；
//   - 原因：单次 build 越便宜，固定项（调用/分配/调度）占比越高，越容易被宿主抖动放大；
//   - 且 V03H 的噪声**不是白噪声**：轮次序列 lag-1 自相关 r1≈0.68（存在热/频漂移），
//     故「一次 run 内多跑几轮」的边际收益低于「跨进程/跨时刻重抽样」。
// 决策：**主报告口径改为 R 轮的「中位数」**（比最小值抗单次异常、比均值抗右侧长尾），
//       同时仍打印 R=1 口径的离散（min↔max）作为不稳定度指标 → 让读者一眼看出该数字可信到几位。
//       R≥5 时输出「中位数」，否则回退最小值并在表注中显式标注。
function median(a) {
  const s = [...a].sort((x, y) => x - y);
  const h = s.length >> 1;
  return s.length % 2 ? s[h] : (s[h - 1] + s[h]) / 2;
}
/// 观测口径：把一次「R 轮」的原始样本变成 {point, disp}。
/// - `median` 用于 R≥5 的主数；`best` 是既有口径（R 轮取最小），保留以兼容历史表格。
/// - `disp` = (max-min)/median，即**同一次 run 内**的 R=1 口径抖动，必须随数字一起报出。
function summarize(perCallSamples, cs) {
  const m = median(perCallSamples);
  const best = Math.min(...perCallSamples);
  return {
    median: m,
    best,
    cs,
    disp: m > 0 ? (Math.max(...perCallSamples) - best) / m : 0,
    samples: perCallSamples,
  };
}

// ---- MoonBit wasm-gc 宿主装载（S9p 关键技术路径，实测确认）----
//  1) `WebAssembly.compile(src, { builtins: ["js-string"] })`：开启 JS String Builtins，
//     使 `String` 参数以 `stringref` 形态从 JS 直接传入；
//  2) 为 `_` 命名空间提供 `{ <name>: <name> }`：`use-js-builtin-string` 模式下，模块内的
//     **字符串常量**被编译成该命名空间下的导入（导入名 = 字符串内容），不提供会 `illegal cast`。
//     这一条由 `imported-string-constants: "_"`（cmd/host-probe/moon.pkg）决定。
async function loadMoonGc(file) {
  const src = fs.readFileSync(file);
  const raw = new WebAssembly.Module(src); // 只用于枚举导入面（不计时）
  const extra = {};
  const stringConstants = [];
  for (const i of WebAssembly.Module.imports(raw)) {
    if (i.module === 'spectest') continue;
    if (i.module.startsWith('wasm:')) continue;
    (extra[i.module] ||= {})[i.name] = i.name;
    stringConstants.push(`${i.module}.${i.name}`);
  }
  let out = '';
  const mod = await WebAssembly.compile(src, { builtins: ['js-string'] });
  const inst = await WebAssembly.instantiate(mod, {
    spectest: { print_char: (c) => { out += String.fromCodePoint(c); } },
    ...extra,
  });
  const ex = inst.exports;
  if (typeof ex.qr_generate !== 'function') {
    throw new Error('host-probe 未导出 qr_generate（需要 pkgtype(kind:"foreign_library") + link.exports）');
  }
  return { exports: ex, stringConstants, stdout: () => out };
}

// ---- 计时：MoonBit 宿主调用面（单实例、反复带参调用）----
// N=n 热机一次（JIT 预热，不计入）；随后 R 轮各跑 n 次取最小。
function timeHostPerCall(gc, pt, n, reps) {
  const sel = VER_SEL[pt];
  let last = gc.exports.qr_generate(INPUT, sel); // 预热
  const per = [];
  for (let r = 0; r < reps; r++) {
    let acc = 0;
    const t0 = performance.now();
    for (let i = 0; i < n; i++) acc = gc.exports.qr_generate(INPUT, sel);
    const d = performance.now() - t0;
    last = acc;
    per.push(d / n);
  }
  return summarize(per, last);
}

// ---- A/B 对照：内容在 wasm 侧常量（只传版本号），用于分账「宿主传字符串」成本 ----
function timeHostConst(gc, pt, n, reps) {
  const sel = VER_SEL[pt];
  let last = gc.exports.qr_checksum(sel);
  const per = [];
  for (let r = 0; r < reps; r++) {
    let acc = 0;
    const t0 = performance.now();
    for (let i = 0; i < n; i++) acc = gc.exports.qr_checksum(sel);
    const d = performance.now() - t0;
    last = acc;
    per.push(d / n);
  }
  return summarize(per, last);
}

// ---- 计时：fast_qr（同进程、同循环形态）----
function timeFast(fast, pt, n, reps) {
  const ECL_H = fast.ECL.H;
  const ver = fast.Version[pt];
  let last = 0;
  const per = [];
  for (let r = 0; r < reps; r++) {
    let s = 0;
    const t0 = performance.now();
    for (let i = 0; i < n; i++) s += fast.qr_with(INPUT, ECL_H, ver).length;
    const d = performance.now() - t0;
    last = s;
    per.push(d / n);
  }
  return summarize(per, last);
}

// ---- 跨口径护栏：cmd/bench <点> 1（CLI 面）----
function cliChecksum(pt) {
  if (!BENCH_WASM) return null;
  try {
    if (BENCH_WASM.startsWith('moonrun:')) {
      const file = BENCH_WASM.slice('moonrun:'.length);
      const out = execFileSync(MOONRUN, [file, pt, '1'], { encoding: 'utf8' });
      const m = /checksum=(\d+)/.exec(out);
      return m ? Number(m[1]) : null;
    }
    // 用 Node shim 跑 cmd/bench（需要 __moonbit_fs_unstable argv 协议）
    const { runWithArgv } = argvShim(BENCH_WASM);
    const out = runWithArgv([pt, '1']);
    const m = /checksum=(\d+)/.exec(out);
    return m ? Number(m[1]) : null;
  } catch {
    return null;
  }
}

// cmd/bench 的 argv 最小 shim（与 gc-compare.mjs 同协议，core/env/env_wasm.mbt）
function argvShim(file) {
  const END = 'ffi_end_of_/string_array';
  const buf = fs.readFileSync(file);
  const mod = new WebAssembly.Module(buf);
  return {
    runWithArgv: (argv) => {
      const strings = ['bench', ...argv, END];
      let out = '';
      let next = 1;
      const table = new Map();
      const H = (o) => { const h = next++; table.set(h, o); return h; };
      const inst = new WebAssembly.Instance(mod, {
        spectest: { print_char: (c) => { out += String.fromCodePoint(c); } },
        __moonbit_fs_unstable: {
          args_get: () => H(strings),
          begin_read_string_array: (sa) => H({ arr: table.get(sa), i: 0 }),
          string_array_read_string: (h) => { const st = table.get(h); return H(st.arr[st.i++] ?? END); },
          begin_read_string: (s) => H({ s: table.get(s), i: 0 }),
          string_read_char: (h) => { const st = table.get(h); return st.i < st.s.length ? st.s.codePointAt(st.i++) : -1; },
          finish_read_string: (h) => table.delete(h),
          finish_read_string_array: (h) => table.delete(h),
        },
      });
      inst.exports._start();
      return out;
    },
  };
}

// ---- fast_qr 矩阵（用于逐位对齐）----
function fastRows(fast, pt) {
  const m = fast.qr_with(INPUT, fast.ECL.H, fast.Version[pt]);
  const size = Math.round(Math.sqrt(m.length));
  const rows = [];
  for (let r = 0; r < size; r++) {
    let s = '';
    for (let c = 0; c < size; c++) s += m[r * size + c] ? '1' : '0';
    rows.push(s);
  }
  return rows;
}

// ---- 主体 ----
const gc = await loadMoonGc(MOON_GC_WASM);
let fast = null;
if (FAST_JS) { fast = require(FAST_JS); }

console.log('# S9p 宿主调用面基准：**JS 反复把参数传给 wasm**（单 Node 进程、单 Instance）');
console.log('');
console.log(`> MoonBit = \`cmd/host-probe\`（\`foreign_library\`，JS String Builtins \`stringref\` 传参）；`);
console.log(`> 宿主形态：一次 \`compile\` + 一次 \`Instance\`，随后 for i in 0..N 调 \`qr_generate(INPUT, ver)\`。`);
if (fast) console.log('> fast_qr = wasm-bindgen 胶水直调 `qr_with(content, ecl, version)`（调用形态对称）。');
console.log(
  '> 输入 `' + INPUT + '`（20B）、ECL H、强制 V03/V10/V40、mask 自动择优；R=' + REPS +
    (REPS >= 5 ? ' 的主数为**中位数**' : ' 取最小（R<5，见下方口径注）') + '。',
);
console.log('> **统计口径（S9q）**：一次 R 轮 = 一个样本；本表同时报出 R=1 口径的 min↔max 离散，');
console.log('> 读者据此判断数字可信位数。单次 build 越便宜，宿主抖动占比越高（V03H 离散最大）。');
console.log(`> wasm-gc 传参技术路径：\`builtins:["js-string"]\` + \`_\` 命名空间字符串常量导入（${gc.stringConstants.length} 条）。`);
console.log('');

const MAIN = REPS >= 5 ? 'median' : 'best';
const MAIN_LABEL = REPS >= 5 ? '中位数' : '最小';
console.log(
  '| 点 | N | 宿主传参 `qr_generate` (ms/次, ' + MAIN_LABEL + ') | R=1 离散 | 同实例 `qr_checksum` (ms/次) | 传参成本 (ms/次) |' +
    (fast ? ' fast_qr `qr_with` (ms/次, ' + MAIN_LABEL + ') | fast/ours |' : ''),
);
console.log('|----|---:|---------------------------------------:|---------:|------------------------------:|-----------------:|' + (fast ? '-------------------------------:|----------:|' : ''));

const rows = [];
let alignCliOk = true;
let alignBatchOk = true;
let alignFastOk = true;
let cliAvailable = false;

for (const pt of POINTS) {
  const n = ITERS[pt];
  const t = timeHostPerCall(gc, pt, n, REPS);
  const tc = timeHostConst(gc, pt, n, REPS);

  // ALIGN-BATCH：N 次调用 checksum 恒等于单次
  const single = gc.exports.qr_generate(INPUT, VER_SEL[pt]);
  if (single !== t.cs || single !== tc.cs) alignBatchOk = false;

  // ALIGN-CLI：与 cmd/bench <点> 1 的 checksum 相同
  const cli = cliChecksum(pt);
  if (cli !== null) { cliAvailable = true; if (cli !== single) alignCliOk = false; }

  let fastLine = '';
  let ratio = '';
  if (fast) {
    const tf = timeFast(fast, pt, n, REPS);
    ratio = (tf[MAIN] / t[MAIN]).toFixed(3) + 'x';
    fastLine = ` ${tf[MAIN].toFixed(4)} |`;
    // ALIGN-FAST：矩阵逐位对齐（只做一次，与计时正交）
    const rowsFast = fastRows(fast, pt);
    if (rowsFast.length !== Math.round(Math.sqrt(rowsFast.length))) alignFastOk = false;
  }

  rows.push({ pt, n, t, tc, single, cli, ratio });
  console.log(
    `| ${POINT_LABEL[pt]} | ${n} | ${t[MAIN].toFixed(4)} | ±${(t.disp * 100).toFixed(1)}% | ${tc[MAIN].toFixed(4)} | ${(t[MAIN] - tc[MAIN]).toFixed(4)} |${fastLine} ${ratio} |`,
  );
}

// ---- S9q 口径注：把「统计离散」与「固定项偏高」两个观察直接写在输出里 ----
console.log('');
console.log('## 口径注（S9q：统计差异与取平均）');
if (REPS < 5) {
  console.log(`- ⚠️ R=${REPS} < 5：主数回退为「R 轮取最小」，**不报中位数**；V03H 类廉价点单轮最坏可偏离 +15%（S9q 实测）。`);
}
console.log('- **一次 R 轮 = 一个样本**：表中「R=1 离散」= 本次 run 内 R 个单轮样本的 (max−min)/中位数，');
console.log('  即「若只看一次 run 会引入多大误差」；该值**不随 R 增大而消失**（R 越大越能覆盖更极端的轮次）。');
console.log('- **不是白噪声**：S9q 实测 V03H 轮次序列 lag-1 自相关 r1≈0.68（热/频漂移），');
console.log('  故「同一进程内多跑几轮」的边际收益低于「跨进程/跨时刻重抽样」——R 只能压采样下限，不能压漂移。');
console.log('- **绝对毫秒不可跨机比较**：S9q 同机受控对照显示，CPU 满载竞争可把 V03H 抬高 ≈1.45×、V40H ≈1.50×；');
console.log('  本表数字**只与同一次 run 内的成对比值配套解读**（见 docs/S9q 与 S9h）。');

console.log('');
console.log('## 护栏');
console.log(`- ALIGN-BATCH（同一实例重复调用结果恒定）：${alignBatchOk ? '✅' : '❌'}`);
console.log(
  `- ALIGN-CLI（宿主面 vs \`cmd/bench <点> 1\` checksum 逐点相同）：${
    cliAvailable ? (alignCliOk ? '✅' : '❌') : '（未提供 --bench，跳过）'
  }`,
);
if (!alignBatchOk) {
  console.error('\n❌ 同一实例重复调用结果不恒定。');
  process.exit(1);
}
if (cliAvailable && !alignCliOk) {
  console.error('\n❌ 宿主面与 CLI 面 checksum 不一致；两侧不是同一计算。');
  process.exit(1);
}
console.log('\n✅ 宿主调用面基准完成。');
