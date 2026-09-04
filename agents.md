# agents.md — AI 协作代理仓库指南

> 本文件为在本仓库工作的 AI 编码代理提供硬性约定。违反下述规则可能导致 **API Key 泄露 / 部署配置破坏**，请优先遵守。

---

## 一、Git 安全（最高优先级）—— 避免 wrangler 配置 / 密钥入库

1. **API Key / Token / Secret 永不写入任何入库文件**
   - Provider API Key 一律走 **Cloudflare Worker Secrets**（`wrangler secret put PROVIDER_*_API_KEY` 或 Dashboard 注入），**不得**写入 `wrangler.jsonc` 的 `vars`（演进 261 / Issue #89，Cloudflare 官方最佳实践）。
   - 同理不得写入 `src/` 源码常量、`.dev.vars.example` 之外的任何文件。
2. **永不提交本地 Secret 文件**
   - `.dev.vars*` / `.env*`（含真实 Key）已加入 `.gitignore`，**禁止** `git add -f` 强制添加。
3. **`wrangler.jsonc` 私人/个人配置一律不入库（硬性）**
   - **禁止提交任何私人配置**：本地 provider 路由（如 `SUBAGENT_PROVIDER`）、模型映射（`DEEPSEEK_PROVIDER_MODEL_NAMES`）、`MODEL_PROVIDER_ROUTES` 个人加权、本地/代理端点 URL、`compatibility_date`、延迟/预算默认值等——这些是部署者个人环境配置，**不得**进入共享仓库。
   - 仓库内 `wrangler.jsonc` 仅保留**非私人基线**（占位 URL 模板）；私人配置留在本地**未提交**状态（`git status` 显示 `M wrangler.jsonc` 属预期，**切勿 `git add` 该文件**）。
   - 改完若需自查：`git diff wrangler.jsonc` 确认无非敏感项之外的私人改动混入暂存区。
4. **新增 Provider 必须走完整 8 触点清单 + 先注入 Secret 再 deploy**
   - 8 触点：`types.ts` 枚举 + `PROVIDER_ENV_PREFIX` / `env.ts` client + providerList / `utils.ts` Dashboard ID / `cloudflare.d.ts` 类型 / `wrangler.jsonc` URL vars / `.dev.vars.example` / README + 文档索引。
   - **必须**先 `wrangler secret put PROVIDER_XXX_API_KEY` 再 deploy——防止「新增 Provider 忘注入 Key → 部署阻断（code 10021）/ 运行期 401」（演进 261 续部署事故教训，详见 `docs/bun_run_deploy_Missing_credentials_报错分析与解决.md`）。
5. **提交前自查**
   - `git status` + `git diff` 检查暂存区/工作区，确认无 wrangler 私人配置或 Secret 文件混入。

---

## 二、项目关键约定

- **文档管理**：遵循 `docs/文档管理规则.md`（命名规范 / 单文档 ≤800 行 / 索引与演进历史同步 / 死链零容忍）。
- **纯个人 / 本地配置调整**（如本地 provider 路由、默认值改动）：只改代码/配置，**不生成 / 不更新项目文档**（README、docs 索引、演进历史、统计）。
- **API Key 管理**：见 `docs/Cloudflare_API_Key_Secret管理_最佳实践与方案评估.md` 与 `docs/Cloudflare_API_Key_Secret管理_批量注入方案与运维.md`。
- **Provider / 模型路由**：单一事实源为 `MODEL_PROVIDER_ROUTES`（env.ts 默认表 + wrangler.jsonc vars），subagent provider 白名单见 `src/agent/subagentShared.ts` `SUBAGENT_PROVIDER_WHITELIST`。
