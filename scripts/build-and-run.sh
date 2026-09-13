#!/usr/bin/env bash
# 后端回归：仅 wasm-gc（本仓库唯一保留的后端）。
#
# 【后端角色约定】：
#   - **wasm-gc = 主推/默认后端**（`moon.mod` 的 `preferred_target`，实际分发形态）→ 对外对比口径。
# 说明：js 与 wasm(WASI) 后端均已按项目决策移除，仅保留 wasm-gc。
# 注意：不要加 native 阶段 —— 需系统 C 编译器，本镜像未安装。
# 模块根无包（方案 3 布局），构建需显式指定包：lib（库）+ cmd/main（CLI）+ cmd/qr-min（S9i 体积探针）。
#
# 语义护栏（S10 §6 T7-c）：cmd/qr-min 的 QR_MIN_CHECKSUM 与 cmd/bench 的 TOTAL_CHECKSUM
# 是「跨优化档/跨后端语义等价」的廉价指纹——同为真则实现未语义漂移。此处由「仅打印」升级为
# 「断言」：不匹配即 CI 失败（避免静默语义回归）。
#
# 用法: bash scripts/build-and-run.sh
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

EXPECT_QR_MIN_CHECKSUM=283   # cmd/qr-min 三基准点单次 build 校验总量（跨优化档恒定）
EXPECT_BENCH_TOTAL=123       # cmd/bench 单点 V03 3 次迭代的 TOTAL_CHECKSUM（同上）

for t in wasm-gc; do
  echo "=== target: $t ==="
  moon build lib --target "$t" --release
  moon build cmd/main --target "$t" --release
  moon build cmd/qr-min --target "$t" --release
  moon run cmd/main --target "$t"
  moon test --target "$t"

  # T7-c：语义指纹断言
  qr_min_out="$(moon run cmd/qr-min --target "$t" --release)"
  qr_min_cs="$(sed -n 's/.*QR_MIN_CHECKSUM=\([0-9]*\).*/\1/p' <<<"$qr_min_out")"
  if [[ "$qr_min_cs" != "$EXPECT_QR_MIN_CHECKSUM" ]]; then
    echo "!! T7-c 失败：QR_MIN_CHECKSUM 期望 $EXPECT_QR_MIN_CHECKSUM，实际 ${qr_min_cs:-<无输出>}" >&2
    exit 1
  fi
  bench_out="$(moon run cmd/bench --target "$t" --release -- V03 3)"
  bench_cs="$(sed -n 's/.*TOTAL_CHECKSUM=\([0-9]*\).*/\1/p' <<<"$bench_out")"
  if [[ "$bench_cs" != "$EXPECT_BENCH_TOTAL" ]]; then
    echo "!! T7-c 失败：TOTAL_CHECKSUM 期望 $EXPECT_BENCH_TOTAL，实际 ${bench_cs:-<无输出>}" >&2
    exit 1
  fi
  echo ">> T7-c 语义指纹一致：QR_MIN_CHECKSUM=$qr_min_cs，TOTAL_CHECKSUM=$bench_cs"
done
