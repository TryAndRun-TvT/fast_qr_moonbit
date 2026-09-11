#!/usr/bin/env bash
# 后端回归：仅 wasm-gc（本仓库唯一保留的后端）。
#
# 【后端角色约定】：
#   - **wasm-gc = 主推/默认后端**（`moon.mod` 的 `preferred_target`，实际分发形态）→ 对外对比口径。
# 说明：js 与 wasm(WASI) 后端均已按项目决策移除，仅保留 wasm-gc。
# 注意：不要加 native 阶段 —— 需系统 C 编译器，本镜像未安装。
# 模块根无包（方案 3 布局），构建需显式指定包：lib（库）+ cmd/main（CLI）+ cmd/qr-min（S9i 体积探针）。
#
# 用法: bash scripts/build-and-run.sh
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

for t in wasm-gc; do
  echo "=== target: $t ==="
  moon build lib --target "$t" --release
  moon build cmd/main --target "$t" --release
  moon build cmd/qr-min --target "$t" --release
  moon run cmd/main --target "$t"
  moon test --target "$t"
done
