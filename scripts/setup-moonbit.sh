#!/usr/bin/env bash
# 安装 MoonBit 工具链并校验可用性。
# 用于 .cnb.yml 的 vscode / push 阶段，避免各阶段重复内嵌安装命令。
#
# 用法: bash scripts/setup-moonbit.sh
set -euo pipefail

echo "Setting up MoonBit toolchain in cloud dev environment..."
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
moon version
