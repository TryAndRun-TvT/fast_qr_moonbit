#!/usr/bin/env bash
# 多后端回归：默认后端 wasm-gc + 兼容后端 wasm(WASI)。
# 说明：js 后端已按项目决策移除（只保留 wasm-gc / wasm 双后端，见 docs 评审记录）。
# 注意：不要加 native 阶段 —— 需系统 C 编译器，本镜像未安装。
# 模块根无包（方案 3 布局），构建需显式指定包：lib（库）+ cmd/main（CLI）。
#
# 用法: bash scripts/build-and-run.sh
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

for t in wasm-gc wasm; do
  echo "=== target: $t ==="
  moon build lib --target "$t" --release
  moon build cmd/main --target "$t" --release
  moon run cmd/main --target "$t"
  moon test --target "$t"
done
