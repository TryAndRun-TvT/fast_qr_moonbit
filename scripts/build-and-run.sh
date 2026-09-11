#!/usr/bin/env bash
# 多后端回归：默认后端 wasm-gc + 兼容后端 wasm(WASI)。
#
# 【后端角色约定】（S9j 起全局统一，避免「比的是哪个后端」歧义）：
#   - **wasm-gc = 主推/默认后端**（`moon.mod` 的 `preferred_target`，实际分发形态）→ 对外对比口径；
#   - wasm(WASI) = 兼容兜底后端 → 仅历史记录，本脚本仍回归构建/测试以保兜底可用。
# 说明：js 后端已按项目决策移除（只保留 wasm-gc / wasm 双后端，见 docs 评审记录）。
# 注意：不要加 native 阶段 —— 需系统 C 编译器，本镜像未安装。
# 模块根无包（方案 3 布局），构建需显式指定包：lib（库）+ cmd/main（CLI）+ cmd/qr-min（S9i 体积探针）。
#
# 用法: bash scripts/build-and-run.sh
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"

for t in wasm-gc wasm; do
  echo "=== target: $t ==="
  moon build lib --target "$t" --release
  moon build cmd/main --target "$t" --release
  moon build cmd/qr-min --target "$t" --release
  moon run cmd/main --target "$t"
  moon test --target "$t"
done
