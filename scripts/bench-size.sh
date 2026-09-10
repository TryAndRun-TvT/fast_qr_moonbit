#!/usr/bin/env bash
# NOTE: 本脚本已纳入仓库并公开可审阅，供复现与评审。
#
# S9f 产物体积对比入口：**统一口径**量测 MoonBit 与 fast_qr 两侧 wasm 产物体积
# （承接 issue #50「同一把尺子」：S9e 统一了性能计时口径，本脚本统一体积口径）。
#
# 与「拿两个 .wasm 文件大小对撞」的区别：
#   1) 两侧产物形态不同（MoonBit `_start` 可执行包 / fast_qr 库导出 + wasm-bindgen 胶水）；
#   2) 两侧 custom 段体积差 60 倍（Rust 侧 8 KB 级 name/target_features vs MoonBit 122 B）；
#   3) 因此按**同一套规则**出五档：① raw ② 剥 custom ③ moon-wasm-opt -Oz
#      ④ 单次调用 wasm+胶水 ⑤ **同功能锚点**（对 fast_qr 另编一个「无胶水单文件 + 打印」裸探针，
#      与 MoonBit `cmd/bench` 同形对撞 —— 这是唯一能排除胶水/依赖面差异的口径）。
#
# 职责:
#   1) 确保 fast_qr-wasm 环境与产物（scripts/setup-fast-qr-wasm-env.sh + build-fast-qr-wasm.sh）；
#   2) 追加编译 **体积探针**（`#[no_mangle] s9f_size_probe`，外部检出副本，不入库）；
#   3) moon build cmd/bench / cmd/main --target wasm --release；
#   4) 调 scripts/wasm-size.mjs 出对照表 + 语义护栏（改写后 `--dump` 逐字节比对）。
#
# 用法:
#   bash scripts/bench-size.sh                 # 全流程（环境 + 构建 + 体积对比）
#   bash scripts/bench-size.sh --no-build      # 跳过构建（产物已就绪，只量测；探针缺则自动补编）
#
# 产物路径可用环境变量覆盖：FAST_QR_WASM_DIR / MOON_BENCH_WASM / MOON_MAIN_WASM / MOON_WASM_OPT
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.cargo/bin:$HOME/.moon/bin:$PATH"

ROOT="${FAST_QR_WASM_DIR:-$HOME/.cache/fast_qr_wasm}"
SRC="$ROOT/fast_qr"
PKG="$ROOT/pkg"
TARGET_DIR="$SRC/target/wasm32-unknown-unknown/release"
PROBE_WASM="$TARGET_DIR/s9f_size_probe.wasm"
HELLO_WASM="$TARGET_DIR/s9f_hello_probe.wasm"
MOON_HELLO_WASM="${MOON_HELLO_WASM:-$ROOT/moonbit_hello_probe/hello.wasm}"
MOON_BENCH_WASM="${MOON_BENCH_WASM:-$PWD/_build/wasm/release/build/cmd/bench/bench.wasm}"
MOON_MAIN_WASM="${MOON_MAIN_WASM:-$PWD/_build/wasm/release/build/cmd/main/main.wasm}"
MOON_WASM_OPT="${MOON_WASM_OPT:-$HOME/.moon/bin/moon-wasm-opt}"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "=== [1/4] fast_qr-wasm 环境 ==="
  bash "$SCRIPT_DIR/setup-fast-qr-wasm-env.sh"
  echo "=== [2/4] 构建 fast_qr qr_with nodejs 产物 ==="
  bash "$SCRIPT_DIR/build-fast-qr-wasm.sh"
  echo "=== [3/4] MoonBit cmd/bench + cmd/main (--target wasm --release) ==="
  moon build cmd/bench --target wasm --release
  moon build cmd/main --target wasm --release
fi

# 体积探针（幂等，外部检出副本 / 临时模块，均不入库）：
#   - s9f_size_probe：无胶水单文件锚点，与 MoonBit cmd/bench 同形（真实调用 QR 核心路径）；
#   - s9f_hello_probe：hello-only 基线，度量两侧「运行时地板」。
if [[ ! -f "$PROBE_WASM" || ! -f "$HELLO_WASM" ]]; then
  echo "=== [3b/4] 编译 fast_qr 体积探针（外部检出副本，不入库）==="
  if [[ ! -d "$SRC/.git" ]]; then
    echo ">>> !! fast_qr 检出缺失，请先跑（不带 --no-build）: bash scripts/bench-size.sh" >&2
    exit 1
  fi
  mkdir -p "$SRC/src/bin"
  cat > "$SRC/src/bin/s9f_size_probe.rs" << 'PROBE_EOF'
//! S9f 体积探针（外部检出副本，不入库）：把一个「真实调用 QR 核心路径」的锚点编进 wasm，
//! 度量 fast_qr 核心代码 + 自带运行时的**体积下限**。s9f：1=V03H / 2=V10H(=0 缺省) / 3=V40H。
fn crate_qr_with_lib(content: &str, ecl: fast_qr::ECL, version: fast_qr::Version) -> Vec<u8> {
    use fast_qr::QRBuilder;
    match QRBuilder::new(content.as_bytes().to_vec()).ecl(ecl).version(version).build() {
        Ok(qr) => {
            let dim = qr.size;
            qr.data[..dim * dim].iter().map(|x| u8::from(x.value())).collect()
        }
        Err(_) => Vec::new(),
    }
}

#[no_mangle]
pub extern "C" fn s9f_size_probe(sel: i32) -> usize {
    let (content, ecl, version) = match sel {
        0 => ("https://example.com/", fast_qr::ECL::H, fast_qr::Version::V03),
        1 => ("https://example.com/", fast_qr::ECL::H, fast_qr::Version::V10),
        _ => ("https://example.com/", fast_qr::ECL::H, fast_qr::Version::V40),
    };
    crate_qr_with_lib(content, ecl, version).len()
}

fn main() {
    println!("{}", s9f_size_probe(2));
}
PROBE_EOF
  cat > "$SRC/src/bin/s9f_hello_probe.rs" << 'HELLO_EOF'
//! S9f 基线探针（外部检出副本，不入库）：一行 println!，不含 QR 逻辑，
//! 度量「Rust 自带 core/alloc/format/panic + 宿主最小面」的体积地板。
#[no_mangle]
pub extern "C" fn s9f_hello_probe() -> usize {
    let mut s = String::from("hello");
    s.push('!');
    s.len() + "x".len()
}

fn main() {
    println!("{}", s9f_hello_probe());
}
HELLO_EOF
  (cd "$SRC" && cargo build --release --target wasm32-unknown-unknown --bin s9f_size_probe --bin s9f_hello_probe)
  # 清理：探针必须是「无胶水单文件」，若因检出副本启用 wasm-bindgen 使其被强制链入，
  # 重新发一次（cargo 会按当前 feature 组合重编，这里直接用 --no-default-features 再 build 一次）。
  (cd "$SRC" && cargo build --release --target wasm32-unknown-unknown --no-default-features \
      --bin s9f_size_probe --bin s9f_hello_probe) || true
fi

# MoonBit empty 基线（hello-only）探针：临时模块（不入库），用于「运行时地板」对照。
if [[ ! -f "$MOON_HELLO_WASM" ]]; then
  echo "=== [3c/4] 编译 MoonBit hello-only 基线探针（临时模块 $ROOT/moonbit_hello_probe，不入库）==="
  mkdir -p "$ROOT/moonbit_hello_probe/cmd/hello"
  cat > "$ROOT/moonbit_hello_probe/moon.mod" << 'MMOD_EOF'
name = "tmp/moonbit_hello_probe"

version = "0.1.0"

preferred_target = "wasm"

supported_targets = "+wasm"
MMOD_EOF
  echo 'pkgtype(kind: "executable")' > "$ROOT/moonbit_hello_probe/cmd/hello/moon.pkg"
  printf '///|\nfn main {\n  println("hello")\n}\n' > "$ROOT/moonbit_hello_probe/cmd/hello/main.mbt"
  (cd "$ROOT/moonbit_hello_probe" && moon build cmd/hello --target wasm --release)
  cp "$ROOT/moonbit_hello_probe/_build/wasm/release/build/cmd/hello/hello.wasm" "$MOON_HELLO_WASM"
fi

echo ""
echo "=== [4/4] 体积对比（同规则，Node 进程内语义护栏）==="
node "$SCRIPT_DIR/wasm-size.mjs" \
  --moon-wasm "$MOON_BENCH_WASM" \
  --moon-main-wasm "$MOON_MAIN_WASM" \
  --fast-wasm "$PKG/fast_qr_bg.wasm" \
  --fast-js "$PKG/fast_qr.js" \
  --fast-raw-wasm "$TARGET_DIR/fast_qr.wasm" \
  --fast-probe-wasm "$PROBE_WASM" \
  --fast-hello-wasm "$HELLO_WASM" \
  --moon-hello-wasm "$MOON_HELLO_WASM" \
  --wasm-opt "$MOON_WASM_OPT"
