# S9b · 性能优化 · O1 实施记录（T2 落地，T1 实测否决）

> 承接 [S9b-性能优化-评估与路线.md](./S9b-性能优化-评估与路线.md)（P1/P2 路线）与
> [S9b-性能优化-再评估与实施建议.md](./S9b-性能优化-再评估与实施建议.md)（T1–T6 实施批建议）。
> 本文记录第一批优化（P1 中 **T2 = S9b O1-b**）的落地与实测，并记录 **T1（S9b O1-a）实测否决**的
> 证据与结论——用「同一把尺子」（S9c 层② N 扫描 marginal）量化前后差异。
> 日期：2026-09-06　｜　范围：只改 `lib/internal/matrix/placement.mbt`（自动择优末段），
> **未动** score/datamasking/qr_build 与公共 API；快照/checksum/层② sha256 全保持。

---

## 0. 一句话结论

- **T2（O1-b）落地**：把「择优后在 base 上再 `apply_mask` 一次（第 9 次整矩阵 copy）」改为**复用最优轮
  已掩码矩阵**、把真实 Format 直接覆写其上 → 省 1 次整矩阵 copy（V40 = 31329 格 × 4B ≈ 125KB）。
  语义逐位不变（快照 + 层② sha256 + 双后端 checksum 全绿）。
- **T1（O1-a 就地翻转）实测否决**：按建议实现「就地 toggle → score → 再 toggle 还原」后，
  V40H marginal **变慢约 8%**（slope 9.007→9.77 ms，整程 384→409ms）——原因见 §3。
  已回退，T1 不再按原形落地（保留为「若改成**单缓冲 + 预判**再评估」的开放项）。
- 净效果（T2 一个点）：V40H marginal slope **9.0074 → 8.8742 ms（≈ −1.5%）**，V03H/V10H 同向略降；
  属小步、低风险、可复现的 O1-b 增量。

---

## 1. 落地内容（T2，`placement.mbt`）

### 1.1 改动点

改前（`create_auto_qr` 末段）：
```
8 轮择优…选 best_mask
create_matrix_format_info(base, size, ecl, best)   // 真实 Format 写进 base
let out = apply_mask(base, size, best)             // 第 9 次整矩阵 copy（125KB@V40）
(out, best)
```
改后：
```
8 轮择优…选 best_mask，并记住 best_masked（该轮 apply_mask 的副本）
create_matrix_format_info(best_masked, size, ecl, best)  // Format 覆写到已掩码矩阵
(best_masked, best)
```

- **等价性依据**：`apply_mask` 只翻 **Data** 类模块；Format/功能图案位不是 Data、mask 不触及。
  故「真实 Format 覆写到**已掩码**矩阵」与「先写 base 再 apply（copy 保留 Format 位）」逐位等价——
  由既有 109 测试 + S6 快照 + 层② sha256（三矩阵与 fast_qr-wasm32 逐字一致）三重验证。
- **无回归面**：不改 score、不更 apply_mask 语义（`apply_mask` 仍返回新矩阵供固定 mask 路径与
  择优轮使用）、不改 `QRCode` 容器；`lib` 公共 `.mbti` 零漂移。

### 1.2 为何收益「小」而非 S9b 预期的大

- S9b §2 内部模型（wasm-gc 单点）估 O1-a 削 8 轮 copy 可把 V40H 择优 6.86ms → 3–4ms；其隐含前提是
  **copy 是大头**。层② marginal 实测（wasm 后端）显示：真正大头是 **8 轮 × score 多趟扫描**（每轮
  ~4 趟全矩阵），copy 的绝对占比有限；去掉 1 次 copy 只带来 ~1.5%——**与 S9b 模型的方向一致但量级
  校正**（详见 §3、§4）。

---

## 2. 验收（全绿）

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon check --deny-warn && moon test            # 109 全绿
for t in wasm-gc wasm; do moon build lib --target $t --release; \
  moon build cmd/bench --target $t --release; moon test --target $t; done
# cmd/bench 默认输出逐字不变：
#   V03H 2000 builds checksum=82000 / V10H 400 →32400 / V40H 40 →9200；TOTAL_CHECKSUM=123600
# 层② 三矩阵 sha256 与 fast_qr-wasm32 逐字一致（V03H 4942f6aa… / V10H 91c85c94… / V40H c3c04930…）
```

---

## 3. T1（O1-a 就地翻转）实测否决：数据与结论

### 3.1 尝试的实现

把每轮 `apply_mask(base,k)`（copy+翻）改为：`apply_mask_inplace(base,k) → score(base) → 再 inplace
还原`，意图免 8 次整矩阵 copy。

### 3.2 实测（同一把尺子：层② N 扫描 R=5，moonrun 整程取最小）

| 形态 | V40H N=40 (ms) | V40H marginal slope (ms/build) | vs 基线 |
|------|---------------:|-------------------------------:|--------:|
| 基线（改前） | 384.02 | 9.0074 | — |
| T1 inplace 双翻转 | **409.43** | ~9.77 | **+~8% 更慢** |
| T2（O1-b，本文） | 381.04 | 8.8742 | −1.5% |

### 3.3 为什么更慢（分析）

- **每轮成本构成**：`copy`（整块 memcpy，带宽型、常数小）远低于 `score` 的 **多趟带判定的全矩阵扫描**
  （每轮 ~4 趟 × 逐格类型/明暗/窗口判定）。
- T1 每轮 = 就地翻(1 趟) + score(4 趟) + 还原翻(1 趟) ≈ **5 趟扫描 + 无 copy**；
  基线每轮 = copy(≈0.3 趟带宽) + 翻(1 趟) + score(4 趟) ≈ **5 趟扫描 + 1 次轻量 copy**。
  即 T1 用「一次真实扫描」去换「一次 memcpy」，**净亏**；且 wasm 下 Array copy 编译器常做整块优化。
- **结论**：O1-a 的收益模型把 copy 高估了；本仓库 wasm 后端上「免 copy」必须**连 score 趟数一起降**
  才有正收益（即 O2/T3 方向），单纯就地翻转不划算。**本文保留 T1 开放但不按原形落地**。

---

## 4. 后续（未做/开放，按再评估建议排序）

- **T3（O2 score 融合减趟）**：`score()` 现 ~4 趟/轮；把 N4 dark 计数并入已有趟（如 `line_rows`/
  `line_cols` 顺带累计）→ 每轮 ~3 趟。这才是把「score 大头」打下来的路径；因 score 是对齐敏感区，
  需**逐步独立提交 + 快照逐位 diff + 层② sha256** 兜底（本文未越界）。
- **T4（mask 判定特化）**：消除每格 `match mask_idx`——可与 T3 同批或独立，先微基准验证收益。
- **T5（wrap_packed 按 size² 分配）**：涉公共 `QRCode.data` 固定容量容器语义，**需先评估接口影响**
  （S9b O3 备注一致），未动。
- 每步沿用 S9c 详细分析 §2 的 N 扫描同一把尺子（R=5、逐点串行、LSQ marginal）记录前后差异。

---

## 5. 汇总

1. **T2（O1-b）已落地**：复用最优轮掩码矩阵 + 真实 Format 覆写其上，省第 9 次整矩阵 copy；语义逐位
   不变，109 测试 + 快照 + 双后端 checksum + 层② sha256 全绿。
2. **实测量级**：V40H marginal 9.0074 → 8.8742ms（≈ −1.5%）；说明 copy 非大头，收益模型需校正
   （大头 = score 多趟扫描）。
3. **T1（O1-a 就地翻转）实测否决**：V40H marginal +~8%；「免 copy」在本后端不如直接优化 score 趟数。
4. 后续建议主攻 **T3（O2 减趟）**，独立提交并以快照逐位 diff + 层② sha256 兜底。

---

## 6. 参考

- 优化路线：[S9b-性能优化-评估与路线.md](./S9b-性能优化-评估与路线.md)
- 实施建议（T1–T6）：[S9b-性能优化-再评估与实施建议.md](./S9b-性能优化-再评估与实施建议.md)
- 同一把尺子/基线：[S9c-性能测试与fast_qr-wasm对比-详细分析.md](./S9c-性能测试与fast_qr-wasm对比-详细分析.md)
- 实码：`lib/internal/matrix/placement.mbt`（create_auto_qr 末段；其余未动）
