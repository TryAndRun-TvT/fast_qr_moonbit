#!/usr/bin/env bash
# 构建 fast_qr v0.14.0 的 Node.js 可调用 wasm 产物（层② D17：qr_with 导出 + wasm-bindgen nodejs 胶水）。
#
# 用途：为层② 对比提供 fast_qr 侧「Node 直调」包（fast_qr.js + fast_qr_bg.wasm），
#   由 scripts/gc-compare.mjs（默认口径，MoonBit 侧 wasm-gc）与 scripts/wasm-compare.mjs
#   （历史口径，MoonBit 侧 wasm/WASI）共用，见 docs/S9j-…。
#   - 检出/复用 fast_qr v0.14.0（commit 53e8c99，钉版本——与 S1-S7 快照对齐的参考同源）；
#   - patch src/wasm.rs 追加 `qr_with(content, ecl, version)`（强制 ECL/version、mask 自动择优，
#     返回 0/1 值矩阵），语义对齐参考 benches/qr.rs 三基准点；
#   - cargo build --release --target wasm32-unknown-unknown --features wasm-bindgen（stable 即可，
#     免 build-std；wasm-opt 为可选瘦身，跳过不影响语义）；
#   - wasm-bindgen --target nodejs 产出 pkg/。
# 参考侧改动只存在于检出副本（默认 $FAST_QR_WASM_DIR），不入本仓库。
#
# 前置：bash scripts/setup-fast-qr-wasm-env.sh（rust wasm32 target + wasm-bindgen-cli）
# 用法: bash scripts/build-fast-qr-wasm.sh
#   FAST_QR_WASM_DIR=<dir>  覆盖检出/产物根目录（默认 $HOME/.cache/fast_qr_wasm）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.cargo/bin:$PATH"

ROOT="${FAST_QR_WASM_DIR:-$HOME/.cache/fast_qr_wasm}"
SRC="$ROOT/fast_qr"
PKG="$ROOT/pkg"
EXPECT_COMMIT="53e8c99"   # fast_qr v0.14.0（与仓库快照参考同版本）
URL="https://github.com/erwanvivien/fast_qr.git"

echo ">>> fast_qr root: $ROOT"
# 1) 检出（复用已有则核验 commit）
if [[ ! -d "$SRC/.git" ]]; then
  mkdir -p "$ROOT"
  git clone "$URL" "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$EXPECT_COMMIT" 2>/dev/null || git -C "$SRC" fetch origin
git -C "$SRC" checkout --detach "$EXPECT_COMMIT"
echo ">>> fast_qr at $(git -C "$SRC" rev-parse --short HEAD)"

# 2) patch wasm.rs：无 qr_with 才追加（幂等）
if ! grep -q "pub fn qr_with" "$SRC/src/wasm.rs"; then
  cat >> "$SRC/src/wasm.rs" << 'PATCH_EOF'

/// S9c 层②基准辅助：强制 ECL/version（mask 留自动择优），返回 0/1 行主序值矩阵。
/// 语义对齐参考 benches/qr.rs（QRBuilder.ecl(H).version(Vxx).build()）。
#[cfg_attr(feature = "wasm-bindgen", wasm_bindgen)]
#[must_use]
pub fn qr_with(content: &str, ecl: crate::ECL, version: crate::Version) -> Vec<u8> {
    crate::QRCode::new(content.as_bytes(), Some(ecl), Some(version), None, None)
        .map(bool_to_u8)
        .unwrap_or_default()
}
PATCH_EOF
  echo ">>> patched wasm.rs with qr_with"
else
  echo ">>> wasm.rs already patched (qr_with present)"
fi

# 3) cargo build（wasm32 target，features=wasm-bindgen；stable 免 build-std）
echo ">>> cargo build (release, wasm32-unknown-unknown, features=wasm-bindgen) ..."
(
  cd "$SRC"
  cargo build --release --target wasm32-unknown-unknown --features wasm-bindgen
)

# 4) wasm-bindgen nodejs 胶水
echo ">>> wasm-bindgen --target nodejs -> $PKG"
rm -rf "$PKG"; mkdir -p "$PKG"
wasm-bindgen --target nodejs --out-dir "$PKG" \
  "$SRC/target/wasm32-unknown-unknown/release/fast_qr.wasm"

# 5) 首验：单行 node require 并调用 qr_with（V40H 矩阵应恰为 177*177=31329 字节）
echo ">>> smoke: node require pkg + qr_with(V40H) length"
out="$(node -e "
const w = require('$PKG/fast_qr.js');
const m = w.qr_with('https://example.com/', w.ECL.H, w.Version.V40);
console.log('LEN=' + m.length);
console.log('KEYS_ECL=' + Object.keys(w.ECL).join(','));
console.log('KEYS_VER=' + Object.keys(w.Version).filter(k => k === 'V03' || k === 'V10' || k === 'V40').join(','));
")"
echo "$out"
echo "$out" | grep -q 'LEN=31329' || { echo "FAIL: qr_with(V40H) length != 31329"; exit 1; }

echo ">>> fast_qr-wasm nodejs package ready: $PKG"
