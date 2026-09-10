#!/usr/bin/env node
// MoonBit WASI 产物的 **Node 进程内** 运行器（S9e：统一调用宿主）。
//
// 背景（为什么需要它）：
//   S9c 层②对比里，两侧调用形态不一致——fast_qr 侧是 Node 进程内 `require` + 直调 qr_with()，
//   MoonBit 侧却是 `moonrun` **子进程**整程（execFileSync，含进程启动）。这使「整程最小时间」
//   两侧不同尺子：MoonBit 侧被计入了一个固定启动开销（实测 12–20%），对比数字被系统性放大。
//
// 本模块把 MoonBit `--target wasm`（WASI preview1）产物直接在**当前 Node 进程**里实例化并调用，
//   与 fast_qr 侧的进程形态对齐，从而做到「同一进程、同一时钟、同一循环形态」的公平计时。
//
// 实现要点（对齐 moonrun 内置宿主 shim 的真实协议，见 docs/S9e-...-实现记录.md §2）：
//   1. 导入面只有两类：`wasi_snapshot_preview1.fd_write`（stdout 捕获）+ `__moonbit_fs_unstable.*`
//      （argv 与字符串/字符串数组读回）。
//   2. argv 协议 = 「回调返回 opaque 句柄」：`args_get()` 返回 argv 数组对象；MoonBit 侧把它当作
//      opaque 句柄原样回传给 `begin_read_string_array(handle)` / `string_read_char(handle)`；
//      `string_array_read_string(handle)` 返回下一个 argv 元素，读完返回 `"ffi_end_of_/string_array"`。
//      句柄就是普通 JS 对象（不跨 wasm 边界做数值化），因此 Node 侧可完整复刻。
//   3. 必须**每次调用新建一个 Instance**：`_start` 只能执行一次（moonrun 亦然）。宿主 shim 的
//      实现按「每实例一套闭包」创建，互不串扰。
//
// 用法（库）:
//   import { loadMoonWasm, runMoonWasm } from './moonbit-wasm-runner.mjs';
//   const mod = loadMoonWasm('/abs/path/bench.wasm');       // 预热编译一次，可复用
//   const out = mod.run(['--dump','V40']);                  // 同步跑一次，返回 { stdout, exitCode }
//
// 用法（CLI，便于手工核对）:
//   node scripts/moonbit-wasm-runner.mjs <bench.wasm> --dump V40
//
// 注意（诚实声明，非平台缺陷）：
//   - 该路径要求产物导入面与 moonrun 内置 shim 一致（`wasi_snapshot_preview1` + `__moonbit_fs_unstable`）。
//     若将来 MoonBit 工具链更换 host 协议（如 moonlight 自定义导入集），需同步更新本 shim；届时
//     `scripts/bench-layer2.sh` 的 `MOON_HOST=moonrun` 回退路径可保底。
//   - 本模块**不参与 CI**（CI 门禁只需 moon 工具链，不引入 Node 宿主细节）；它是性能对比脚本的一部分。

import fs from 'node:fs';

/// 构造一次性的宿主 shim。`argv` 为本次运行要暴露给 MoonBit 程序的全量 argv
/// （惯例：argv[0] = 产物名，其后为业务参数）。返回 { imports }。
function makeHostImports(ref, argv, onStdout) {
  // ---- argv：opaque 句柄回调协议（对齐 moonrun 内置 shim）----
  const fsOps = {
    // argv 入口：返回 argv 数组本体，后续作为 opaque 句柄被原样回传。
    args_get: () => argv,
    // 字符串读回（MoonBit 侧以 JS string 作为句柄，无额外包装）。
    begin_read_string: (s) => ({ s, i: 0 }),
    string_read_char: (h) => (h.i >= h.s.length ? -1 : h.s.charCodeAt(h.i++)),
    finish_read_string: () => {},
    // 字符串数组读回：句柄为 { arr, i }，读完返回哨兵串。
    begin_read_string_array: (arr) => ({ arr, i: 0 }),
    string_array_read_string: (h) =>
      h.i >= h.arr.length ? 'ffi_end_of_/string_array' : h.arr[h.i++],
    finish_read_string_array: () => {},
    // 字符串/字节数组「创建」侧回调（cmd/bench 路径未用到，防御性提供，
    // 保证与其他 MoonBit 程序（如需把结果写回宿主）共用本模块时不缺导入）。
    begin_create_string: () => ({ s: '' }),
    string_append_char: (h, c) => {
      h.s += String.fromCharCode(c);
    },
    finish_create_string: (h) => h.s,
    begin_create_byte_array: () => ({ arr: [] }),
    byte_array_append_byte: (h, b) => {
      h.arr.push(b);
    },
    finish_create_byte_array: (h) => new Uint8Array(h.arr),
    begin_read_byte_array: (arr) => ({ arr, i: 0 }),
    byte_array_read_byte: (h) => (h.i >= h.arr.length ? -1 : h.arr[h.i++]),
    finish_read_byte_array: () => {},
  };

  const preview1 = {
    // 只捕获 stdout（fd=1）；stderr 交给宿主进程，便于排错。
    fd_write: (fd, iovsPtr, iovsLen, nwrittenPtr) => {
      const mem = ref.inst.exports.memory;
      const dv = new DataView(mem.buffer);
      let total = 0;
      for (let i = 0; i < iovsLen; i++) {
        const base = dv.getUint32(iovsPtr + i * 8, true);
        const len = dv.getUint32(iovsPtr + i * 8 + 4, true);
        if (fd === 1) onStdout(Buffer.from(mem.buffer, base, len).toString('utf8'));
        total += len;
      }
      dv.setUint32(nwrittenPtr, total, true);
      return 0;
    },
  };

  return { wasi_snapshot_preview1: preview1, __moonbit_fs_unstable: fsOps };
}

/// 预热：编译一次 WebAssembly.Module（可跨多次 run 复用），返回带 run() 的句柄。
export function loadMoonWasm(wasmPath) {
  const bytes = fs.readFileSync(wasmPath);
  const module = new WebAssembly.Module(bytes);
  return {
    path: wasmPath,
    /// 同步跑一次（新 instance + 新 shim），返回 { stdout, exitCode, ms }。
    /// `argv` 不含 argv[0]；argv[0] 会自动补成产物 basename。
    run(argv = []) {
      let stdout = '';
      const ref = { inst: null };
      const imports = makeHostImports(ref, [wasmPath.split('/').pop(), ...argv], (s) => {
        stdout += s;
      });
      const t0 = performance.now();
      const inst = new WebAssembly.Instance(module, imports);
      ref.inst = inst;
      let exitCode = 0;
      try {
        inst.exports._start();
      } catch (e) {
        exitCode = 1;
        stdout += `\n[runner] wasm trap: ${e && e.message ? e.message : e}`;
      }
      return { stdout, exitCode, ms: performance.now() - t0 };
    },
  };
}

/// 便捷：一次性读取文件并同步运行（不含 Module 复用的场景）。
export function runMoonWasm(wasmPath, argv = []) {
  return loadMoonWasm(wasmPath).run(argv);
}

// ---- CLI ----
if (import.meta.url === `file://${process.argv[1]}`) {
  const [, , wasmPath, ...rest] = process.argv;
  if (!wasmPath) {
    console.error('usage: node scripts/moonbit-wasm-runner.mjs <wasm> [args...]');
    process.exit(2);
  }
  const r = runMoonWasm(wasmPath, rest);
  process.stdout.write(r.stdout);
  process.exit(r.exitCode);
}
