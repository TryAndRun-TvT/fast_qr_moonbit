#!/usr/bin/env bash
# 安装 MoonBit 工具链并校验可用性（云原生开发环境初始化用；.cnb.yml 的 vscode 阶段调用）。
#
# 用法: bash scripts/setup-moonbit.sh
#
# 【版本可复现性（适配评估 §6-P0，2026-09-23）】
#   官方 CLI 服务**只提供 `latest` / `nightly` 两个通道**——按具体版本号下载会 404
#   （实测 `binaries/0.1.20260920/...`、`0.10.14`、`v0.10.14`、`0.1.20260920` 均 404；
#    仅 `latest` / `nightly` 返回 200）。因此**无法**用 `MOONBIT_INSTALL_VERSION` 钉死具体版本。
#   本脚本据此改为：「装通道（默认 `latest`）+ **装后断言实际版本 == 期望版本**」，
#   把「静默漂移」变成「显式提示 / 可选失败」：
#     - 期望版本 = `MOON_EXPECTED_VERSION`（默认见下），**升级时刻意更新它**；
#     - 断言失败**默认仅告警**（与 docs-date-check.sh 的「提示不阻断」同风格）；
#       需要强复现的场合设 `MOON_STRICT_VERSION=1` ⇒ 版本不符即非零退出；
#     - dev 通道：设 `MOONBIT_INSTALL_DEV=1`（官方安装脚本自身支持）。
#   依据与复跑：docs/01-规格/moonbit-工具链版本与特性适配评估.md §5-H1 / §6-P0。
set -euo pipefail

echo "Setting up MoonBit toolchain in cloud dev environment..."
curl -fsSL https://cli.moonbitlang.cn/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
moon version

MOON_EXPECTED_VERSION="${MOON_EXPECTED_VERSION:-0.1.20260920}"
actual="$(moon version | head -1 | awk '{print $2}')"

if [[ "$actual" == "$MOON_EXPECTED_VERSION" ]]; then
  echo ">>> ✅ 工具链版本与期望一致：moon $actual"
else
  echo ">>> ⚠️ 工具链版本漂移：实际 moon $actual ≠ 期望 $MOON_EXPECTED_VERSION" >&2
  echo "    处置：先跑 bash scripts/toolchain-probe.sh 查看新增/潜伏告警（--warn-list +a），" >&2
  echo "          再决定是否更新 MOON_EXPECTED_VERSION（本仓未钉版，原因见脚本头注释）。" >&2
  if [[ "${MOON_STRICT_VERSION:-0}" == "1" ]]; then
    echo ">>> MOON_STRICT_VERSION=1 ⇒ 版本漂移视为失败。" >&2
    exit 1
  fi
fi
