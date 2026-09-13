#!/usr/bin/env node
// T3-c：固化解码向量生成器（S10 T3-c）。
//
// 背景：`scripts/qr-decode-check.mjs` 用第三方解码器（jsqr）证明矩阵「符合 QR 规范语义」，
//   但它依赖 npm 依赖，**不进 push CI**（口径见 S10 §T3 与附录 D）。参考库里同类跨实现回归
//   （`bytes.rs` 的 PNG 断言、`qrcode` crate 交叉）**已被作者删除**，教训是：跨实现回归极易腐化，
//   必须收敛为「**少量固定向量 + 明确复跑路径**」。
//
// 本脚本把 T3-d 语料（`cmd/bench --dump-case`）的矩阵**指纹**与**期望原文**固化进
//   `lib/s6_decode_vectors_test.mbt`，使仓库**不引入任何新依赖**即可回归：
//   一旦实现的矩阵输出漂移（无论是 bug 还是「修复」），指纹断言立刻变红，提示重跑解码审计。
//
// 指纹口径：0/1 行主序矩阵**去换行拼接**后的 sha256（与 `--dump` 协议一致、与宿主无关）。
// 参考 commit：fast_qr v0.14.0 `53e8c99`（仅作旁证；解码期望原文由**输入本身**决定，不来自参考）。
//
// 用法（需先 `moon build cmd/bench --target wasm-gc --release`）：
//   node scripts/snapshot_gen_decode_vectors.mjs [--moon-gc <bench.wasm>] [--moonrun <path>] [--write]
//   （不带 --write 只打印；`--write` 才改 lib/ 下测试文件）

import { execFileSync } from 'node:child_process';
import { writeFileSync, readFileSync } from 'node:fs';

const arg = (n, d) => {
  const i = process.argv.indexOf(n);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : d;
};
const WASM = arg('--moon-gc', '_build/wasm-gc/release/build/cmd/bench/bench.wasm');
const MOONRUN = arg('--moonrun', process.env.MOONRUN || 'moonrun');
const WRITE = process.argv.includes('--write');

const run = (args) => execFileSync(MOONRUN, [WASM, ...args], { encoding: 'utf8', maxBuffer: 1 << 28 });

// 指纹口径（与 Node 侧脚本无关，可由 `*_test.mbt` 只用 pub API 复算）：
//   FNV-1a 64 位 over「0/1 行主序拼接串」，以 16 位小写 hex 表示。
//   选 FNV-1a 而非 sha256：MoonBit core 无 sha256，而本向量只需要「**稳定漂移检测**」，
//   FNV-1a 在 64 位下碰撞概率对 ~11 条向量可忽略；且实现 10 行、黑盒可复算。
// Node 侧用 BigInt 复刻同一算法，保证两侧一致。
const OFFSET = 0xcbf29ce484222325n;
const PRIME = 0x100000001b3n;
const MASK64 = (1n << 64n) - 1n;
function fnv1a64(str) {
  let h = OFFSET;
  for (const ch of str) {
    h ^= BigInt(ch.codePointAt(0) & 0xff);
    h = (h * PRIME) & MASK64;
  }
  return h.toString(16).padStart(16, '0');
}


function loadCase(i) {
  const out = run(['--dump-case', String(i)]).trimEnd().split('\n');
  const meta = out.find((l) => l.startsWith('QR_CASE '));
  if (!meta) throw new Error(`case ${i} 无 QR_CASE 行`);
  const g = (k) => new RegExp(`${k}=([^ ]+)`).exec(meta)[1];
  const li = out.findIndex((l) => l.startsWith('QR_MATRIX'));
  const size = Number(/size=(\d+)/.exec(out[li])[1]);
  const rows = out.slice(li + 1, li + 1 + size);
  if (rows.length !== size) throw new Error(`case ${i} 行数 ${rows.length} != ${size}`);
  const grid = rows.join('');
  return {
    index: i, kind: g('kind'), mode: g('mode'), ecl: g('ecl'), version: g('version'),
    size, content_len: Number(g('content_len')), fnv: fnv1a64(grid),
  };
}

// 选取向量：① grid 的**四角 + 中段**（覆盖三模式 × 极端版本）
//          ② **全部 6 组 auto 靶点**（v5 `select_capacity` 模式语义 bug 的直接回归面）
const total = Number(/QR_CASE_TOTAL=(\d+)/.exec(run(['--dump-case', 'list']))[1]);
const all = Array.from({ length: total }, (_, i) => loadCase(i));
const gridIdx = all.filter((c) => c.kind === 'grid');
const autoIdx = all.filter((c) => c.kind === 'auto');
const picked = [
  ...gridIdx.filter((c) => [0, 3, 15, 32, 47].includes(c.index)),
  ...autoIdx,
];

const lines = [];
lines.push('///|');
lines.push('/// s6_decode_vectors_test.mbt —— T3-c 固化解码向量（黑盒）；**由脚本生成，禁止手改**。');
lines.push('///');
lines.push('/// 生成器：`node scripts/snapshot_gen_decode_vectors.mjs --write`');
lines.push('/// 前置：`moon build cmd/bench --target wasm-gc --release`');
lines.push('/// 参考 commit：fast_qr v0.14.0 `53e8c99`（旁证；期望原文由输入决定，不来自参考）');
lines.push('///');
lines.push('/// 这些向量是**独立正确性证据的固定形态**：`scripts/qr-decode-check.mjs`（jsqr）已证明');
lines.push('/// 下列矩阵「能被第三方解码器读回原文」，本文件把该结论固化为**无 npm 依赖可回归**的指纹。');
lines.push('///');
lines.push('/// 指纹 = **FNV-1a 64** over `0/1` 行主序拼接串（16 位小写 hex）。任何矩阵输出漂移都会变红。');
lines.push('/// 期望内容同样固化：`content` 必须是该矩阵交给第三方解码器后**读回的原文**');
lines.push('///   （Numeric→全 `9`、Alphanumeric→全 `A`、Byte→全 `z`，长度见 `content`）。');
lines.push('///');
lines.push('/// 复跑路径（矩阵漂移时）：');
lines.push('///   1) `bash scripts/test-audit.sh decode` —— 用 jsqr 重新验证语义（需 `npm i jsqr`）');
lines.push('///   2) `node scripts/snapshot_gen_decode_vectors.mjs --write` —— 确认语义无误后刷新指纹');
lines.push('/// 铁律：**语义未重新验证前，禁止直接刷新指纹**（否则把回归洗成「新基线」）。');
lines.push('');
lines.push('///|');
lines.push('/// 单条固化向量：`--dump-case index` 的矩阵指纹 + 期望读回内容 + 参数指纹。');
lines.push('struct DecodeVector {');
lines.push('  index : Int');
lines.push('  kind : String');
lines.push('  mode : String');
lines.push('  ecl : String');
lines.push('  version : String');
lines.push('  size : Int');
lines.push('  content : String');
lines.push('  fnv : String');
lines.push('}');
lines.push('');
lines.push('///|');
lines.push('/// 固化向量表（脚本生成，见文件头复跑路径）。');
lines.push('fn decode_vectors() -> Array[DecodeVector] {');
lines.push('  [');
for (const c of picked) {
  const padChar = c.mode === 'Numeric' ? '9' : c.mode === 'Alphanumeric' ? 'A' : 'z';
  const content = padChar.repeat(c.content_len);
  lines.push('    DecodeVector::{');
  lines.push(`      index: ${c.index},`);
  lines.push(`      kind: "${c.kind}",`);
  lines.push(`      mode: "${c.mode}",`);
  lines.push(`      ecl: "${c.ecl}",`);
  lines.push(`      version: "${c.version}",`);
  lines.push(`      size: ${c.size},`);
  lines.push(`      content: "${content}",`);
  lines.push(`      fnv: "${c.fnv}",`);
  lines.push('    },');
}
lines.push('  ]');
lines.push('}');
lines.push('');
lines.push('///|');
lines.push('/// UInt64 → 16 位小写 hex（core 无现成实现，本文件自持）。');
lines.push('fn decode_hex16(v : UInt64) -> String {');
lines.push('  let sb = StringBuilder()');
lines.push('  let mut shift = 60');
lines.push('  while shift >= 0 {');
lines.push('    // 每 4 位取一个 nibble');
lines.push('    let nib = ((v >> shift).to_int()) & 0xF');
lines.push("    sb.write_char(if nib < 10 { (nib + 48).unsafe_to_char() } else { (nib - 10 + 97).unsafe_to_char() })");
lines.push('    shift -= 4');
lines.push('  }');
lines.push('  sb.to_string()');
lines.push('}');
lines.push('');
lines.push('///|');
lines.push('/// FNV-1a 64 位（与生成器 Node 侧同算法；16 位小写 hex 输出）。');
lines.push('fn decode_fnv1a64(s : String) -> String {');
lines.push('  let mut h : UInt64 = 0xCBF29CE484222325UL');
lines.push('  // s.to_bytes() 已 deprecated；FNV 只需**确定性地**逐字节迭代，');
lines.push('  // 用 char 的低 8 位 UTF-8 等价位（本向量内容全为 ASCII，无编码歧义）。');
lines.push('  for c in s {');
lines.push('    h = h ^ (c.to_int() & 0xFF).to_uint64()');
lines.push('    h = h * 0x100000001B3UL');
lines.push('  }');
lines.push('  decode_hex16(h)');
lines.push('}');
lines.push('');
lines.push('///|');
lines.push('/// 版本短名（`V1`..`V40`）→ 公共 `Version` 枚举（`V01`..`V40`）。');
lines.push('fn decode_version(name : String) -> Version {');
lines.push('  match name {');
lines.push('    "V1" => Version::V01');
lines.push('    "V5" => Version::V05');
lines.push('    "V10" => Version::V10');
lines.push('    _ => Version::V40');
lines.push('  }');
lines.push('}');
lines.push('');
lines.push('///|');
lines.push('/// 按向量参数**重新构建** QR 码，只用 pub API 逐格取明暗拼出矩阵串。');
lines.push('fn decode_rebuild(v : DecodeVector) -> String {');
lines.push('  let mode = match v.mode {');
lines.push('    "Numeric" => Mode::Numeric');
lines.push('    "Alphanumeric" => Mode::Alphanumeric');
lines.push('    _ => Mode::Byte');
lines.push('  }');
lines.push('  let ecl = match v.ecl {');
lines.push('    "L" => ECL::L');
lines.push('    "M" => ECL::M');
lines.push('    "Q" => ECL::Q');
lines.push('    _ => ECL::H');
lines.push('  }');
lines.push('  let b = QRBuilder::from_string(v.content).mode(mode).ecl(ecl)');
lines.push('  // kind 决定是否强制版本：`grid` 强制定长版本，`auto` 走自动最小适配（bug 靶点）。');
lines.push('  // 注：`version` 字符串已固化了实际选中版本，仅供失败信息定位用。');
lines.push('  // grid 语料强制其固化版本；auto 语料走自动最小适配（`select_capacity` 的 bug 靶点）。');
lines.push('  let r = if v.kind == "auto" {');
lines.push('    b.build()');
lines.push('  } else {');
lines.push('    b.version(decode_version(v.version)).build()');
lines.push('  };');
lines.push('  match r {');
lines.push('    Ok(q) => {');
lines.push('      let sb = StringBuilder()');
lines.push('      let mut row = 0');
lines.push('      while row < q.size() {');
lines.push('        let mut col = 0');
lines.push('        while col < q.size() {');
lines.push("          sb.write_char(if q.get(row, col).value() { '1' } else { '0' })");
lines.push('          col += 1');
lines.push('        }');
lines.push('        row += 1');
lines.push('      }');
lines.push('      sb.to_string()');
lines.push('    }');
lines.push('    Err(_) => ""');
lines.push('  }');
lines.push('}');
lines.push('');
lines.push('///|');
lines.push('/// T3-c：对每条固化向量重建矩阵并断言 FNV-1a 指纹 + 尺寸一致（模块.函数 + 参数指纹）。');
lines.push('/// 说明：本测试**不依赖第三方解码器**（那是 `test-audit.sh decode` 的角色）；');
lines.push('/// 它锁的是「修复 `select_capacity` 模式语义后，矩阵输出保持稳定」，');
lines.push('/// 防止未来改动静默改回旧行为（旧行为下 auto 靶点语料**不可解码**）。');
lines.push('test "s6_decode_vectors_frozen" {');
lines.push('  let vs = decode_vectors()');
lines.push('  assert_eq(vs.length(), ' + String(picked.length) + ')');
lines.push('  for v in vs {');
lines.push('    let got = decode_rebuild(v)');
lines.push('    if got.length() != v.size * v.size {');
lines.push('      fail(');
lines.push('        "s6_decode_vectors_frozen case \\{v.index} \\{v.mode}/\\{v.ecl}/\\{v.version}: 矩阵长度 \\{got.length()} != size^2 \\{v.size * v.size}",');
lines.push('      )');
lines.push('    }');
lines.push('    let got_fnv = decode_fnv1a64(got)');
lines.push('    if got_fnv != v.fnv {');
lines.push('      fail(');
lines.push('        "s6_decode_vectors_frozen case \\{v.index} \\{v.mode}/\\{v.ecl}/\\{v.version} size=\\{v.size} content_len=\\{v.content.length()}: fnv=\\{got_fnv} want=\\{v.fnv}（矩阵漂移；先跑 bash scripts/test-audit.sh decode 复核语义）",');
lines.push('      )');
lines.push('    }');
lines.push('  }');
lines.push('}');
lines.push('');
if (WRITE) {
  const path = 'lib/s6_decode_vectors_test.mbt';
  const prev = (() => { try { return readFileSync(path, 'utf8'); } catch { return ''; } })();
  writeFileSync(path, lines.join('\n'));
  console.log(`写入 ${path}：${picked.length} 条向量（total cases ${total}）`);
  if (prev) console.log('（覆盖既有文件；请用 git diff 复核）');
} else {
  console.log(lines.join('\n'));
  console.error(`\n[未写盘] ${picked.length} 条向量，total cases ${total}；加 --write 才落地。`);
}
