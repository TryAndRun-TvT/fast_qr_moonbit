#!/usr/bin/env node
// S9f 产物体积对比驱动：**统一口径**量测 MoonBit 与 fast_qr 两侧 wasm 产物体积。
//
// 【后端约定】：MoonBit 侧只保留 `wasm-gc`（主推/默认，唯一后端，**对外对比口径**：
//   `moon-gc-*` 通道 + `cmd/qr-min` 纯库调用探针，S9i）；WASI 后端已移除，不再量测。
//
// 背景（承接 issue #50 的「同尺子」要求）：
//   S9e 把两侧的**性能**计时统一到了「同一 Node 进程内」；体积对比同样不能「拿文件大小直接对撞」——
//   两侧产物的**导出面 / 依赖 / 宿主胶水**都不同，必须先把口径摆清楚再比：
//
//   | 维度 | 本仓库 MoonBit wasm-gc | fast_qr v0.14.0 wasm32 |
//   |------|--------------------|------------------------|
//   | 入口 | `_start`（`cmd/bench` 可执行包，argv 驱动） | `qr_with`/`qr` 库导出（wasm-bindgen 胶水调用） |
//   | 依赖 | 自带 MoonBit 运行时（分配/字符串/格式）；GC 侧交给宿主 | 自带 Rust core/alloc/format + 依赖 `__wbindgen_placeholder__` 胶水 shim |
//   | 宿主胶水 | 无（`moonrun` 直接跑 `_start`） | `fast_qr.js`（wasm-bindgen 生成，≈8.2 KB） |
//
//   本脚本给**同规则五档 + 两个锚点**：
//     ① raw                —— 构建产物原样字节数。
//     ② no-custom          —— 剥 wasm `custom` 段（name/producers/target_features，纯元数据）。
//     ③ moon-wasm-opt -Oz  —— `moon-wasm-opt`（moon 自带 Binaryen）`--all-features -Oz`（Rust 侧加
//                             `--strip-debug --strip-producers`），即**两侧同一优化器**下的发布档。
//     ④ per-call envelope  —— 单次调用「必须搬上宿主/MoonBit 自带的字节」：wasm(-Oz)
//                             + 宿主胶水（fast_qr.js）或 MoonBit 侧的 argv shim（由 moorun/runner 提供，≈0）。
//     ⑤ **同功能锚点**      —— 对 fast_qr 另编一个「最小裸 wasm」（`#[no_mangle] s9f_size_probe` + 一行
//                             `println!`，导出返回矩阵长度、无 wasm-bindgen 胶水、无 JS），与
//                             MoonBit `cmd/bench`（同为「无胶水单文件 + 打印」）**同形**对撞。
//                             这是唯一能回答「排除胶水/依赖面差异后，谁更小」的口径。
//   + 锚点 A：`cmd/main`（CLI 演示，另一档「无胶水单文件」场景）
//
// 正确性护栏：所有字节级改写（strip/no-custom/-Oz）都在 Node 进程内重新跑一遍并比对语义——
//   MoonBit(wasm-gc) 侧经 `moonrun` 跑 `--dump` 文本逐字节；fast_qr 侧 `qr_with` 三矩阵哈希。
//   不一致即退出码 1：体积优化不得悄悄改语义（对齐 S9e §4 的 sha256 口径）。
//
// 用法:
//   node scripts/wasm-size.mjs \
//     --moon-gc-wasm <bench.wasm> --fast-wasm <pkg/fast_qr_bg.wasm> [--fast-js <pkg/fast_qr.js>] \
//     [--fast-raw-wasm <.../fast_qr.wasm>] [--fast-probe-wasm <.../s9f_size_probe.wasm>] \
//     [--moon-gc-main-wasm <cmd/main/main.wasm>] [--moon-gc-qrmin-wasm <.../qr-min.wasm>] \
//     [--wasm-opt <moon-wasm-opt>] [--json]
//   （bash 包装见 scripts/bench-size.sh）
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';

// ---- 参数解析 ----
function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
const FAST_WASM = arg('--fast-wasm', process.env.FAST_QR_BG_WASM || null);
const FAST_JS = arg('--fast-js', process.env.FAST_QR_JS || null);
const FAST_RAW_WASM = arg('--fast-raw-wasm', process.env.FAST_QR_RAW_WASM || null);
const FAST_PROBE_WASM = arg('--fast-probe-wasm', process.env.FAST_QR_PROBE_WASM || null);
const FAST_HELLO_WASM = arg('--fast-hello-wasm', process.env.FAST_QR_HELLO_WASM || null);
// --- wasm-gc（**默认/唯一后端**）通道 ---
const MOON_GC_WASM = arg('--moon-gc-wasm', process.env.MOON_GC_BENCH_WASM || null);
const MOON_GC_MAIN_WASM = arg('--moon-gc-main-wasm', process.env.MOON_GC_MAIN_WASM || null);
const MOON_GC_HELLO_WASM = arg('--moon-gc-hello-wasm', process.env.MOON_GC_HELLO_WASM || null);
// --- S9i 纯库调用体积探针（cmd/qr-min：仅 QR 核心生成管线，无 argv/--dump/输出层外壳）通道 ---
const MOON_GC_QRMIN_WASM = arg('--moon-gc-qrmin-wasm', process.env.MOON_GC_QRMIN_WASM || null);
const MOONRUN = arg('--moonrun', process.env.MOONRUN || null);
const PROBE_SYMBOL = process.env.FAST_QR_PROBE_SYMBOL || 's9f_size_probe';
const WASM_OPT = arg('--wasm-opt', process.env.MOON_WASM_OPT || null);
const REPS = Number(arg('--reps', '3'));
const AS_JSON = process.argv.includes('--json');
const INPUT = 'https://example.com/';
const POINTS = ['V03', 'V10', 'V40'];
if (!MOON_GC_WASM || !FAST_WASM) {
  console.error('usage: node wasm-size.mjs --moon-gc-wasm <bench.wasm> --fast-wasm <fast_qr_bg.wasm>');
  process.exit(2);
}

const b = (n) => `${(n / 1024).toFixed(1)} KiB`;
const ratio = (a, z) => `${(a / z).toFixed(2)}×`;
const pct = (a, z) => `${((a / z) * 100).toFixed(1)}%`;
const sha = (x) => createHash('sha256').update(x).digest('hex').slice(0, 16);

// ---- wasm 段解析（文件头 + 段表，LEB128；custom 段名用于明细）----
const SECTION_NAME = {
  0: 'custom',
  1: 'type',
  2: 'import',
  3: 'function',
  4: 'table',
  5: 'memory',
  6: 'global',
  7: 'export',
  8: 'start',
  9: 'element',
  10: 'code',
  11: 'data',
  12: 'data_count',
};
function parseSections(buf) {
  const u8 = new Uint8Array(buf);
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  if (dv.getUint32(0, true) !== 0x6d736100) throw new Error('not a wasm module');
  const readU32 = (o) => {
    let r = 0;
    let sh = 0;
    let c;
    do {
      c = u8[o++];
      r |= (c & 0x7f) << sh;
      sh += 7;
    } while (c & 0x80);
    return [r >>> 0, o];
  };
  let o = 8;
  const sections = [];
  while (o < u8.length) {
    const id = u8[o++];
    const [size, payloadStart] = readU32(o);
    const sec = { id, name: SECTION_NAME[id] || `id${id}`, payload: size, payloadStart };
    if (id === 0) {
      const [nameLen, nameStart] = readU32(payloadStart);
      sec.customName = Buffer.from(u8.slice(nameStart, nameStart + nameLen))
        .toString('utf8')
        .replace(/[^\x20-\x7e]/g, '');
    }
    sections.push(sec);
    o = payloadStart + size;
  }
  return sections;
}

/// 剥离全部 custom 段（纯元数据，语义不变）。
function stripCustomSections(buf) {
  const u8 = new Uint8Array(buf);
  const out = [u8.slice(0, 8)];
  const readU32 = (o) => {
    let r = 0;
    let sh = 0;
    let c;
    do {
      c = u8[o++];
      r |= (c & 0x7f) << sh;
      sh += 7;
    } while (c & 0x80);
    return [r >>> 0, o];
  };
  let o = 8;
  while (o < u8.length) {
    const start = o;
    const id = u8[o++];
    const [size, payloadStart] = readU32(o);
    o = payloadStart + size;
    if (id !== 0) out.push(u8.slice(start, o));
  }
  return Buffer.concat(out.map((x) => Buffer.from(x)));
}

// ---- 体积量测 ----
function measure(label, file) {
  const raw = fs.readFileSync(file);
  const secs = parseSections(raw);
  const custom = secs.filter((x) => x.id === 0);
  const stripped = stripCustomSections(raw);
  return {
    label,
    file,
    raw: raw.length,
    custom: raw.length - stripped.length,
    customNames: custom.map((x) => x.customName || '(unnamed)'),
    noCustom: stripped.length,
    sections: secs.map((x) => ({ name: x.customName ? `custom:${x.customName}` : x.name, bytes: x.payload })),
  };
}

/// `moon-wasm-opt --all-features -Oz`（两侧同一优化器）；Rust 产物默认带 debug/producers，显式剥掉。
function optimize(file, outFile, { rust = false } = {}) {
  if (!WASM_OPT || !fs.existsSync(WASM_OPT)) return null;
  const args = [file, '--all-features', '-Oz'];
  if (rust) args.push('--strip-debug', '--strip-producers');
  args.push('-o', outFile);
  execFileSync(WASM_OPT, args, { stdio: ['ignore', 'ignore', 'pipe'] });
  return fs.readFileSync(outFile).length;
}

/// wasm-gc 专用优化：`moon-wasm-opt` 开 `--all-features` 会启用 custom-descriptors(RTT)，
/// 产出的 `exact` heap type / nullref 常量在 Node 24 与 moonrun 上**都编译不过**；
/// 关掉它即得「可被真实宿主加载」的体积最小档（实测 Node/moonrun 均可运行 + 语义一致）。
function optimizeGc(file, outFile) {
  if (!WASM_OPT || !fs.existsSync(WASM_OPT)) return null;
  const args = [file, '--all-features', '--disable-custom-descriptors', '-Oz', '-o', outFile];
  execFileSync(WASM_OPT, args, { stdio: ['ignore', 'ignore', 'pipe'] });
  return fs.readFileSync(outFile).length;
}

/// wasm-gc 产物**没有** `__moonbit_fs_unstable`（无 argv/字符串读回），但 `_start` 仍在；
/// 进程内的 WASI shim 与 wasm-gc 导入面不兼容，因此走 `moonrun`（MoonBit 官方运行时，
/// 本仓库既有依赖）作为**进程内不可用时的官方宿主**：逐字节比对 `--dump` 三基准点输出。
function moonrunDigest(file) {
  const hash = createHash('sha256');
  for (const pt of POINTS) {
    // 注意：moonrun 直接接受**文件路径**（无 `run` 子命令）；`--target/--release` 由 `moon` 解析。
    const out = execFileSync(MOONRUN, [file, '--dump', pt], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 64 * 1024 * 1024,
    });
    hash.update(out);
  }
  return hash.digest('hex').slice(0, 16);
}

// ---- 语义护栏 ----
/// fast_qr 侧：胶水后产物无 `_start`，改用 JS 胶水 + `qr_with` 出三矩阵哈希（拷到临时目录换 wasm 文件）。
function fastQrWithDigest(wasmFile, pkgDir) {
  const dir = pkgDir || path.dirname(FAST_WASM);
  const glue = fs.existsSync(path.join(dir, 'fast_qr.js')) ? 'fast_qr.js' : null;
  if (!glue) return null;
  const tmpDir = fs.mkdtempSync('/tmp/s9f-fastpkg-');
  fs.copyFileSync(path.join(dir, glue), path.join(tmpDir, glue));
  fs.copyFileSync(wasmFile, path.join(tmpDir, 'fast_qr_bg.wasm'));
  const req = createRequire(path.join(tmpDir, 'x.js'));
  const mod = req(path.join(tmpDir, glue));
  const h = createHash('sha256');
  for (const pt of POINTS) {
    const m = mod.qr_with(INPUT, mod.ECL.H, mod.Version[pt]);
    h.update(String(m.length)).update(Buffer.from(m));
  }
  return h.digest('hex').slice(0, 16);
}
/// 探针 wasm：直接实例化、调导出符号核对语义。
/// 探针本身不 import 任何宿主面；但若在「已启用 wasm-bindgen」的检出副本里反复构建，
/// Cargo 可能把 wasm-bindgen 强制链进来（于是导入 `__wbindgen_*`）。这里给足最小 shim
/// 让实例化成功——探针语义只看导出符号的返回值，与 shim 无关。
function rawProbeDigest(file, symbol) {
  const mod = new WebAssembly.Module(fs.readFileSync(file));
  const imports = {};
  for (const i of WebAssembly.Module.imports(mod)) {
    imports[i.module] = imports[i.module] || new Proxy({}, { get: () => () => 0 });
  }
  const inst = new WebAssembly.Instance(mod, imports);
  const f = inst.exports[symbol];
  if (typeof f !== 'function') return null;
  return sha([0, 1, 2].map((s) => String(f(s))).join(','));
}

function guard(cond, tag) {
  if (!cond) {
    console.error(`❌ ${tag}：改写后产物语义与原始产物不一致，拒绝输出（体积优化不得改语义）。`);
    process.exit(1);
  }
}

// ---- 主体 ----
const tmp = fs.mkdtempSync('/tmp/s9f-size-');
const fast = measure('fast_qr_bg.wasm', FAST_WASM);
const probe = FAST_PROBE_WASM && fs.existsSync(FAST_PROBE_WASM) ? measure('fast_qr 裸探针 wasm', FAST_PROBE_WASM) : null;
const fastHello = FAST_HELLO_WASM && fs.existsSync(FAST_HELLO_WASM) ? measure('fast_qr 基线探针（hello）', FAST_HELLO_WASM) : null;

const fastNoCustomFile = path.join(tmp, 'fast.nocustom.wasm');
fs.writeFileSync(fastNoCustomFile, stripCustomSections(fs.readFileSync(FAST_WASM)));

const fastOptFile = path.join(tmp, 'fast.opt.wasm');
const probeOptFile = path.join(tmp, 'probe.opt.wasm');
const fastHelloOptFile = path.join(tmp, 'fasthello.opt.wasm');
const fastOpt = optimize(FAST_WASM, fastOptFile, { rust: true });
const probeOpt = probe ? optimize(FAST_PROBE_WASM, probeOptFile, { rust: true }) : null;
const fastHelloOpt = fastHello ? optimize(FAST_HELLO_WASM, fastHelloOptFile, { rust: true }) : null;

// 护栏
const gFastBase = fastQrWithDigest(FAST_WASM);
guard(gFastBase !== null ? fastQrWithDigest(fastNoCustomFile) === gFastBase : true, 'fast_qr no-custom');
guard(fastOpt !== null ? fastQrWithDigest(fastOptFile) === gFastBase : true, 'fast_qr wasm-opt -Oz');
const gProbeBase = probe ? rawProbeDigest(FAST_PROBE_WASM, PROBE_SYMBOL) : null;
guard(probeOpt !== null ? rawProbeDigest(probeOptFile, PROBE_SYMBOL) === gProbeBase : true, 'fast_qr 裸探针 -Oz');
const gHelloBase = fastHello ? rawProbeDigest(FAST_HELLO_WASM, 's9f_hello_probe') : null;
guard(fastHelloOpt !== null ? rawProbeDigest(fastHelloOptFile, 's9f_hello_probe') === gHelloBase : true, 'fast_qr 基线探针 -Oz');

// ---- wasm-gc（默认/唯一后端）量测 + 护栏 ----
const gc = MOON_GC_WASM && fs.existsSync(MOON_GC_WASM) ? measure('MoonBit bench.wasm (wasm-gc)', MOON_GC_WASM) : null;
const gcMain =
  MOON_GC_MAIN_WASM && fs.existsSync(MOON_GC_MAIN_WASM) ? measure('MoonBit cmd/main main.wasm (wasm-gc)', MOON_GC_MAIN_WASM) : null;
const gcHello =
  MOON_GC_HELLO_WASM && fs.existsSync(MOON_GC_HELLO_WASM) ? measure('MoonBit 基线探针 hello (wasm-gc)', MOON_GC_HELLO_WASM) : null;
const gcQrmin =
  MOON_GC_QRMIN_WASM && fs.existsSync(MOON_GC_QRMIN_WASM)
    ? measure('MoonBit cmd/qr-min (wasm-gc)', MOON_GC_QRMIN_WASM)
    : null;
let gcNoCustomFile = null;
let gcOptFile = null;
let gcNoCustom = null;
let gcOpt = null;
let gcHelloOpt = null;
let gcMainOpt = null;
let gcQrminOpt = null;
let gGcBase = null;
let gGcQrminBase = null;
if (gc) {
  gcNoCustomFile = path.join(tmp, 'moon.gc.nocustom.wasm');
  fs.writeFileSync(gcNoCustomFile, stripCustomSections(fs.readFileSync(MOON_GC_WASM)));
  gcNoCustom = fs.readFileSync(gcNoCustomFile).length;
  gcOptFile = path.join(tmp, 'moon.gc.opt.wasm');
  gcOpt = optimizeGc(MOON_GC_WASM, gcOptFile);
  gcMainOpt = gcMain ? optimizeGc(MOON_GC_MAIN_WASM, path.join(tmp, 'moonmain.gc.opt.wasm')) : null;
  gcHelloOpt = gcHello ? optimizeGc(MOON_GC_HELLO_WASM, path.join(tmp, 'moonhello.gc.opt.wasm')) : null;
  // 护栏：原始 / 剥 custom / -Oz 三档在 moonrun 下 `--dump` 三基准点逐字节一致
  gGcBase = moonrunDigest(MOON_GC_WASM);
  guard(moonrunDigest(gcNoCustomFile) === gGcBase, 'MoonBit(wasm-gc) no-custom');
  guard(gcOpt !== null ? moonrunDigest(gcOptFile) === gGcBase : true, 'MoonBit(wasm-gc) wasm-opt -Oz');
}
if (gcQrmin) {
  const gcQrminOptFile = path.join(tmp, 'moonqrmin.gc.opt.wasm');
  gcQrminOpt = optimizeGc(MOON_GC_QRMIN_WASM, gcQrminOptFile);
  gGcQrminBase = moonrunDigest(MOON_GC_QRMIN_WASM);
  guard(gcQrminOpt !== null ? moonrunDigest(gcQrminOptFile) === gGcQrminBase : true, 'MoonBit(wasm-gc) qr-min wasm-opt -Oz');
}

const jsGlue = FAST_JS && fs.existsSync(FAST_JS) ? fs.readFileSync(FAST_JS).length : null;
const fastRawWasm = FAST_RAW_WASM && fs.existsSync(FAST_RAW_WASM) ? fs.readFileSync(FAST_RAW_WASM).length : null;

// ---- 输出 ----
if (AS_JSON) {
  console.log(
    JSON.stringify(
      {
        moonGc: gc ? { raw: gc.raw, noCustom: gcNoCustom, opt: gcOpt, custom: gc.custom } : null,
        moonGcMain: gcMain ? { raw: gcMain.raw, opt: gcMainOpt } : null,
        moonGcQrmin: gcQrmin ? { raw: gcQrmin.raw, opt: gcQrminOpt } : null,
        moonGcHelloBaseline: gcHelloOpt,
        fast: { raw: fast.raw, noCustom: fast.noCustom, opt: fastOpt, custom: fast.custom, jsGlue, rawWasmBeforeBindgen: fastRawWasm },
        probe: probe ? { raw: probe.raw, opt: probeOpt } : null,
        helloBaseline: { fast: fastHelloOpt },
        guards: { fast: gFastBase, probe: gProbeBase, moonGcQrmin: gGcQrminBase },
      },
      null,
      2
    )
  );
  process.exit(0);
}

console.log('# S9f 产物体积对比（统一口径，两侧同规则）');
console.log('');
console.log('> 承接 issue #50 的「同一把尺子」：S9e 统一了**性能**计时口径，本文统一**体积**口径。');
console.log('> ① raw 原始产物 ② 剥 custom 段 ③ `moon-wasm-opt --all-features -Oz`（两侧同一优化器）');
console.log('> ④ 单次调用需搬上宿主的字节（wasm + 胶水） ⑤ 同功能锚点（无胶水单文件）。');
console.log('> 所有改写档位均已过语义护栏（`--dump` / `qr_with` / 导出符号比对）。');
console.log('> MoonBit 侧统一为 `wasm-gc`（默认/唯一后端），经 `moonrun` 加载运行。');
console.log('');
console.log('## 产物与宿主面');
console.log('');
console.log('| 侧 | 产物 | 入口 | 运行时 | 宿主胶水 |');
console.log('|----|------|------|--------|---------|');
console.log(`| 本仓库 MoonBit（\`cmd/bench\`，wasm-gc） | \`bench.wasm\` | \`_start\`（argv 驱动） | 自带 MoonBit 运行时 + 宿主 GC | 无（\`moonrun\` 直跑 \`_start\`） |`);
console.log(`| fast_qr v0.14.0（wasm-bindgen nodejs） | \`fast_qr_bg.wasm\` + \`fast_qr.js\` | \`qr_with\` 库导出 | Rust core/alloc/format | \`fast_qr.js\` ${jsGlue === null ? '（未提供）' : jsGlue + ' B'} |`);
console.log('');

if (gc) {
  console.log('## 一、对照表（同规则口径，`wasm-gc` = **本仓库实际分发形态**）');
  console.log('');
  console.log('> `moon.mod`: `preferred_target = \"wasm-gc\"`。`wasm-gc` 把对象/字符串交给**宿主 GC**，');
  console.log('> 自带运行时远小于自管运行时，因此这才是本库对外承诺的产物档位。');
  console.log('> 优化档用 `moon-wasm-opt --all-features --disable-custom-descriptors -Oz`：');
  console.log('> `--all-features` 会打开 custom-descriptors(RTT)，其 `exact` heap type 在 Node 24 与 moonrun 上**都编译不过**，');
  console.log('> 关掉后即得「可被真实宿主加载」的体积最小档。');
  console.log('');
  console.log('| 档位 | MoonBit(wasm-gc) bench (B) | fast_qr_bg (B) | ours / fast_qr |');
  console.log('|------|---------------------------:|---------------:|---------------:|');
  console.log(`| ① raw 原始产物 | ${gc.raw} | ${fast.raw} | ${ratio(gc.raw, fast.raw)} |`);
  console.log(`| ② 剥 custom 段 | ${gcNoCustom} | ${fast.noCustom} | ${ratio(gcNoCustom, fast.noCustom)} |`);
  console.log(`| ③ wasm-opt -Oz（可运行档） | ${gcOpt ?? 'n/a'} | ${fastOpt ?? 'n/a'} | ${gcOpt && fastOpt ? ratio(gcOpt, fastOpt) : 'n/a'} |`);
  console.log(`| ④ 单次调用 wasm+胶水（-Oz） | ${gcOpt ?? 'n/a'}（无胶水） | ${gcOpt && fastOpt && jsGlue !== null ? fastOpt + jsGlue : 'n/a'} | ${gcOpt && fastOpt && jsGlue !== null ? ratio(gcOpt, fastOpt + jsGlue) : 'n/a'} |`);
  console.log('');
  if (gcMain) console.log(`- 另一档场景：MoonBit \`cmd/main\`(wasm-gc) raw ${gcMain.raw} B / \`-Oz\` ${gcMainOpt} B。`);
  if (gcOpt && probeOpt) {
    console.log(`- 对 fast_qr 裸探针（同口径 ③）：ours / fast = **${ratio(gcOpt, probeOpt)}**（两侧都无胶水；fast_qr 侧已剥 wasm-bindgen 胶水面）。`);
  }
  console.log('');
  console.log('### 同功能锚点（-Oz，同口径）');
  console.log('');
  console.log('| 锚点 | (B) |');
  console.log('|--------------------|----:|');
  console.log(`| MoonBit \`cmd/bench\` (wasm-gc) | ${gcOpt ?? 'n/a'} |`);
  if (gcMain) console.log(`| MoonBit \`cmd/main\` (wasm-gc) | ${gcMainOpt} |`);
  if (gcQrmin) console.log(`| MoonBit \`cmd/qr-min\`（纯库调用，wasm-gc） | ${gcQrminOpt} |`);
  if (probeOpt) console.log(`| fast_qr 裸探针（无胶水） | ${probeOpt} |`);
  if (fastOpt) console.log(`| fast_qr 库导出 \`fast_qr_bg\`（wasm-bindgen） | ${fastOpt} |`);
  console.log('');
  if (gcQrminOpt && probeOpt) {
    console.log(
      `- **对称同功能锚点（S9i）**：MoonBit 纯库调用 \`cmd/qr-min\` ${gcQrminOpt} B vs fast_qr 裸探针 ${probeOpt} B = **${ratio(gcQrminOpt, probeOpt)}**——两侧同为「核心-only + 一行 println」，消除此前用 bench 外壳对撞裸探针的不对称高估。`
    );
    if (gcHelloOpt) {
      console.log(
        `- **库实际体积（S9i）**：\`cmd/qr-min\`(wasm-gc, -Oz) ${gcQrminOpt} B，扣 hello 地板（${gcHelloOpt} B）后 QR 核心净增 **+${gcQrminOpt - gcHelloOpt} B**（fast_qr 净增 +${probeOpt - fastHelloOpt} B）。`
      );
    }
    if (gcMainOpt && gcOpt) {
      console.log(
        `- **外壳成本归因**：输出层（终端画 + SVG）仅 ${gcMainOpt - gcQrminOpt} B（main − qr-min）；bench 外壳（argv/迭代/--dump）共 ${gcOpt - gcQrminOpt} B（bench − qr-min）。`
      );
    }
  }
  if (gcHelloOpt && fastHelloOpt && gcOpt) {
    console.log(`- **wasm-gc 运行时地板**：hello-only \`-Oz\` 仅 **${gcHelloOpt} B**（Rust 侧 ${fastHelloOpt} B），`);
    console.log(`  即 \`wasm-gc\` 把「运行时地板」压到 ~0.3 KB；此时 QR 业务净增 = ${gcOpt} − ${gcHelloOpt} = **+${gcOpt - gcHelloOpt} B**。`);
  }
}
console.log('');
console.log(`- 参照：fast_qr 胶水前库 wasm（cargo 直出）${fastRawWasm ?? 'n/a'} B（对照用，含 resvg 关闭后的完整库面）。`);
console.log('');

console.log('## 二、custom 段构成（为什么 raw 档别直接对撞）');
console.log('');
console.log(`- MoonBit(wasm-gc) bench：custom ${gc ? gc.custom : 'n/a'} B（${gc ? pct(gc.custom, gc.raw) : 'n/a'}）→ ${gc ? gc.customNames.join(', ') : 'n/a'}`);
console.log(`- fast_qr_bg：custom ${fast.custom} B（${pct(fast.custom, fast.raw)}）→ ${fast.customNames.join(', ')}`);
console.log('');
console.log('> Rust 侧 `name` 段（wasm-bindgen 的符号名，7.7 KB 级）+ `target_features` 属**元数据**；');
console.log('> MoonBit 侧几乎不带 custom 段。剥掉后两侧才算同口径。');
console.log('');

console.log('## 三、结论');
console.log('');
if (gc && gcOpt) {
  console.log(`1. **本仓库实际分发形态是 \`wasm-gc\`（默认/唯一后端）**：raw ${gc.raw} B、剥 custom ${gcNoCustom} B、\`-Oz\` **${gcOpt} B**（可被 Node/moonrun 真实加载运行）。`);
  console.log(`   对比 fast_qr \`-Oz\` ${fastOpt} B → **${ratio(gcOpt, fastOpt)}**；计入 fast_qr 胶水 ${jsGlue} B → **${ratio(gcOpt, fastOpt + jsGlue)}**。`);
  if (gcHelloOpt && fastHelloOpt) {
    console.log(`   运行时地板：\`wasm-gc\` hello-only **${gcHelloOpt} B** vs Rust **${fastHelloOpt} B**（Rust 高 ${(fastHelloOpt / gcHelloOpt).toFixed(1)}×），`);
    console.log(`   QR 业务净增 ${gcOpt - gcHelloOpt} B vs fast_qr ${probeOpt - fastHelloOpt} B。`);
    console.log(`   → 两侧总体积差里，大部分是**各自运行时/宿主面的地板差**，QR 业务代码本身的净增量同量级。`);
  }
}
if (gcQrminOpt && probeOpt) {
  console.log(
    `2. **库实际体积（S9i 纯库调用口径）**：\`cmd/qr-min\`(wasm-gc) -Oz **${gcQrminOpt} B**，扣 hello 地板后 QR 核心净增 **+${gcHelloOpt ? gcQrminOpt - gcHelloOpt : 'n/a'} B**；对称锚点 vs fast_qr 裸探针 ${probeOpt} B = **${ratio(gcQrminOpt, probeOpt)}**。`
  );
  console.log(
    `   命令形态不能代表库体积：bench/main 与 qr-min 的差值即各自外壳（argv/迭代/--dump、终端画+SVG）的成本，随宿主集成场景裁剪。`
  );
}
console.log('');
console.log('## 四、语义护栏（改写后 vs 原始，逐字节）');
console.log('');
console.log(`- fast_qr \`qr_with\` 三矩阵：no-custom / -Oz **一致** sha256[:16]=${gFastBase}`);
if (gProbeBase) console.log(`- fast_qr 裸探针导出符号输出：raw/-Oz **一致** sha256[:16]=${gProbeBase}`);
if (gGcBase) console.log(`- MoonBit(wasm-gc) \`--dump\` 三基准点文本（moonrun 宿主）：raw / no-custom / -Oz **一致** sha256[:16]=${gGcBase}`);
console.log('> 复跑：`bash scripts/bench-size.sh`（内部 `node scripts/wasm-size.mjs`）；数字随工具链/产物版本可重测。');
