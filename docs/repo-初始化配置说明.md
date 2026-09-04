# fast_qr_moonbit 仓库初始化配置说明

> 本文档汇总本次仓库初始化与配置过程，便于后续维护与回溯。

## 一、背景

本仓库 `fast_qr_moonbit` 为 MoonBit 二维码相关项目，由 ISSUE #1「init repo」驱动完成初始化，主要复用 `chathub-server` 仓库的 AI 协作配置并配置本仓库的云原生构建。

## 二、执行过程

### 1. Clone 源仓库

克隆配置来源仓库 `chathub-server`（仅作配置参考源，不会入库）:

```
https://cnb.cool/tryandrun/web_dev/chat_hub/chathub-server
```

### 2. 复制 AI 协作配置

从 `chathub-server` 复制以下 AI 协作配置到本仓库根目录：

- **`.codebuddy/`** — CodeBuddy 自定义命令
  - `.codebuddy/commands/commit.md` — 提交辅助命令
  - `.codebuddy/commands/doc-refine.md` — 文档优化辅助命令
- **`agents.md`** — AI 编码代理仓库指南（Git 安全、项目约定等硬性约束）

### 3. 配置 `.cnb.yml`

在本仓库根目录生成云原生构建配置文件，要求如下：

| 项目 | 配置 | 说明 |
|------|------|------|
| CPU 核数 | `2` | `runner.cpus: 2`（省核配置） |
| Docker 服务 | 不启用 | 未声明 `docker` 环境与 DinD `services`，使用缺省构建镜像 |

配置基于 `chathub-server` 的开发模板调整，采用 `$` 兜底分支 + `vscode` 云原生开发事件。

## 三、生成结果

本仓库根目录现包含：

```
├── .cnb.yml        # 云原生构建配置（cpu=2，无 docker 服务）
├── .codebuddy/     # CodeBuddy 命令配置
│   └── commands/
├── agents.md       # AI 协作代理指南
└── docs/           # 文档目录
```

## 四、注意事项

- `.codebuddy/` 与 `agents.md` 内容来源于 `chathub-server`，其中的项目特定规则（如 wrangler/Cloudflare 相关约定）仅作参考，后续需结合本仓库 MoonBit 实际项目调整。
- 如需调整构建并发核数或启用 Docker，修改 `.cnb.yml` 中 `runner.cpus` 与 `services` 即可。
