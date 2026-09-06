# S9d · 与 moonbit 生态 QR 包（qrc / moonqr / moonbitqrcode）性能对比 · 实现记录

> 承接 [S9d-与moonbit生态QR包性能对比-方案.md](./S9d-与moonbit生态QR包性能对比-方案.md)
> （层②同语言延伸方案）与本仓库性能基线
> [S9c-性能测试与fast_qr-wasm对比-详细分析.md](./S9c-性能测试与fast_qr-wasm对比-详细分析.md)。
> 本记录落地**首跑对比**：`bobzhang/qrc@0.1.1`、`naoto24kawa/moonqr@0.2.0`、`PaiGack/moonbitqrcode@0.1.0`
> 经 `moon add` 引入独立对比模块、与本仓库 `cmd/bench` wasm 产物在同一 `moonrun` 宿主计时。
> 日期：2026-09-06　｜　范围：**只运行既有 cmd/bench/对比驱动并记录**，本仓库 lib 未再改；
> 结论与方案 §5「不预设位次」一致，且**暴露 3 个生态包在「同尺寸同语义可比」上的硬约束**（见 §3）。

---

## 0. 一句话结论

- **同尺寸、同语义（强制 V03/V10/V40 + ECL H + mask 自动择优 + 完整 Format/版本）可比子集只有「本仓库 vs moonqr」**；
  实测本仓库 **2.5–4.1× 更快**（V40H 单次 9.46ms vs 38.29ms；V03H 0.318 vs 0.805ms，R=5 取最小）。
- **qrc 与 moonbitqrcode 暂无法与本仓库做同口径对齐对比**，原因（实测核实）：
  - `qrc` 公开完整路径仅**自动版本**（`encode_with_ec`→`generate_qr_with_mask` 才含 mask/Format）；
    `encode_with_mode_and_ec` 强制版本**只 place_data、无 mask/Format**（qrc 自带 README 亦标注
    「No format information / No masking」）；且自动版本对 20B@H 返回 **V2(size=25)**，
    低于理论最小 V3(29)——疑似容量/模式口径差异，需可解码性核验。
  - `moonbitqrcode` lib 公开面 **仅 encode_low/medium/high = L/M/Q**（`LibLevel::H` 外部不可构造，
    MoonBit 报 read-only），且固定 `Plan(…, Mask::of_int(0))` **不做择优**；只可比「自动版本 + 固定
    mask0」参考口径，不能与自动择优方排名。
- 因此本记录给出：**① 可信对比（ours vs moonqr）数字表；② qrc/moonbitqrcode 参考口径表 + 不可比
  原因；③ 对本仓库的结论：同语言生态内当前也**不落后**（moonqr 是对手位）。**

---

## 1. 方法（对齐方案 §3 + S9/S9c 口径）

### 1.1 对比模块与产物

```bash
# 仓库外独立模块（不入库，对齐层② fast_qr 检出模式）
mkdir -p ~/.cache/moonbit_qr_compare && cd ~/.cache/moonbit_qr_compare
moon new compare && cd compare
moon add bobzhang/qrc@0.1.1 naoto24kawa/moonqr@0.2.0 PaiGack/moonbitqrcode@0.1.0
# moon.pkg import 三方（@qrc/@mq/@mqr）+ main.mbt 驱动（argv: lib N [ver]）
moon build cmp --target wasm --release   # 或 .mooncakes 内直接 build 三方（本记录用 /tmp 对比模块）
```

本记录实测环境 = `/tmp/moon-scratch/qrcompare`（含三包 `.mooncakes` 检出），`moon 0.1.20260827`。

### 1.2 计时与消费口径（沿用 S9/S9c）

- 输入 `https://example.com/`（20B），ECL H，V03/V10/V40（能强制才强制）。
- 每方每点循环 N 次 build，**消费每次结果**（累加矩阵边长进 checksum，防死代码消除）；
  输出 `SIZE=<边长>` + `TOTAL_CHECKSUM=<int>`。
- 宿主 `moonrun` 子进程整程计时，**R=5 取最小**（同层②）；单点迭代 N=2000/400/40（同 S9 默认档）。
- 「单次(ms/build)」= 整程最小/N（含 moonrun 启动摊销；双方同宿主、同 N，摊薄一致，可直接比）。
- 结果消费口径：本仓库侧沿用 `cmd/bench`（size+代表格+元数据 checksum）；三包侧为「累加矩阵边长
  checksum + 输出 SIZE」——与 fast_qr 层②侧只累加长度同量级，偏置可忽略（两侧都强制消费了每次 build）。
- 本仓库侧 = 既有 `cmd/bench --target wasm` 产物（同协议，`moonrun bench.wasm Vxx N`）。

---

## 2. 实测数字

### 2.1 可信对比（同尺寸同语义：本仓库 vs moonqr，R=5 取最小，moonrun）

| 方 | 点 | N | 整程最小(ms) | 单次(ms/build) | 每模块(µs) | vs 本仓库(单次比) |
|----|----|--:|------------:|---------------:|-----------:|------:|
| 本仓库 | V03H | 2000 | 635.2 | 0.3176 | 0.378 | 1.00× |
| moonqr | V03H | 2000 | 1610.7 | 0.8054 | 0.958 | **2.54×** |
| 本仓库 | V10H | 400 | 475.3 | 1.1883 | 0.366 | 1.00× |
| moonqr | V10H | 400 | 1714.1 | 4.2852 | 1.319 | **3.61×** |
| 本仓库 | V40H | 40 | 378.2 | 9.4550 | 0.302 | 1.00× |
| moonqr | V40H | 40 | 1531.7 | 38.2925 | 1.222 | **4.05×** |

- 两侧都做了真实 8 轮 mask 择优 + Format/版本信息 + 完整纠错（同尺寸、同 ECL、同输入）。
- **结论**：本仓库 V03→V40 全程快 moonqr **2.5–4.1×**；差距随版本增大（与层②对 fast_qr 的差距方向
  相反，说明 moonqr 的大版本成本结构更重）。本数字与 S9c 层②口径（本仓库 V40H 单次 ≈9.0ms）自洽。

### 2.2 参考口径（qrc / moonbitqrcode —— 不可同口径对齐，仅记录其公开路径表现）

| 方 | 路径 | N | 整程最小(ms) | 单次(ms/build) | SIZE | 备注 |
|----|------|--:|------------:|---------------:|-----:|------|
| qrc | `encode_with_ec(H)` 自动版本 | 2000 | 1191.3 | 0.5957 | 25 | ⚠️ V2 < 理论最小 V3(29)；README 自述无 mask/Format 于该 API 族 |
| moonbitqrcode | `encode_high(=Q)` 自动版本 | 2000 | 94.9 | 0.0474 | 25 | ⚠️ lib 固定 mask0（无择优）+ 仅自动版本 + 无 H 公共构造 |

> **为什么这两行不与 §2.1 排名**：
> - 尺寸不同（25 vs 29/57/177）→ 每 build 工作量不同；且 qrc 的 20B@H 落到 V2 属**容量/模式口径
>   可疑**（需可解码性核验后才能当作“正确的 QR 编码”来计时）。
> - qrc 强制版本路径无 mask/Format；moonbitqrcode 无择优（固定 mask0）→ 与「自动择优」语义不等价，
>   直接排名会把「没做择优」误读成「更快」。
> - 故两行仅作**生态包公开路径可跑性与量级参考**，标注在案、不进入与本仓库的同口径结论。

---

## 3. 生态包可比性硬约束（实测核实，供后续/他人复用）

| 包 | 强制版本 | 强制 ECL | mask 择优 | 完整 Format/版本信息 | 可比性判定 |
|----|---------|---------|-----------|---------------------|-----------|
| qrc | 有 API 但**路径无 mask/Format**（`encode_with_mode_and_ec` 只 place_data） | 有（make_ec_level_*） | 仅自动版本完整路径有（generate_qr_with_mask） | 仅自动版本路径有 | ❌ 无法与本仓库同口径对齐 |
| moonqr | ✅ `encode(text, ec, Some(v))` | ✅ EcLevel::H | ✅（自动） | ✅ | ✅ **可比** |
| moonbitqrcode | ❌ lib 仅自动版本（内部 coding.Plan 可强但非稳定公共面） | ⚠️ lib 仅 L/M/Q（H 外部不可构造） | ❌ 固定 mask0 | ✅（Plan 内部） | ❌ 仅参考口径 |

> 这本身是「调研/评估」结论的实证落地：S9d 方案 §6 预判的三处不确定点全部命中，且给出准确形态
> （qrc 强制版本缺 mask/Format、moonbitqrcode H 不可构造 + 固定 mask0、moonqr 是唯一干净可对比方）。

---

## 4. 与既有基准的关系（同一把尺子）

- 本仓库侧数字与 S9c 层②/详细分析一致（V40H 单次 ≈9.0–9.5ms，wasm+moonrun 口径），本次未改 lib，
  故 §2.1 即「本仓库 vs moonqr」的新增同语言对比基线。
- 若后续 S9b T3/T4 落地，可**直接复用本对比模块**重跑 §2.1 表，观察对 moonqr 的差距收窄（本表即
  优化前后同一把尺子；同样也可复跑 S9c bench-layer2 对 fast_qr）。

---

## 5. 验收与门禁（沿用 AGENTS §二.4）

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon fmt && moon check --deny-warn && moon test        # 109 全绿
for t in wasm-gc wasm; do moon build cmd/bench --target $t --release; done
```
- 本记录纯跑测 + 文档，lib/scripts 未动；`cmd/bench` 默认输出与既有记录一致（82000/32400/9200）。
- 死链零容忍：新增文档须同步 README「文档」索引 + roadmap（见 §7）。

---

## 6. 汇总与后续

1. **可信结论**：同尺寸同语义（强制版本 + H + 自动择优 + 完整输出）下，本仓库快 moonqr 2.5–4.1×。
2. **生态现状**：qrc 0.1.1 与 moonbitqrcode 0.1.0 的公共 API 尚不足以做与本仓库的同口径对比
   （mask/版本/ECL 约束见 §3）——本记录将其列为参考口径并说明原因，不夸大结论。
3. **后续可选**：
   - 对 qrc/moonbitqrcode 做「自动版本可解码性」核验（若输出本身不可解码，则其计时仅代表内部管线
     成本、不能代表“生成可用 QR”）；属参考性质量审计，非本仓库性能义务。
   - S9b T3（score 减趟）落地后重跑 §2.1，回填对 moonqr 的收窄数据。

---

## 7. 参考

- 方案：[S9d-与moonbit生态QR包性能对比-方案.md](./S9d-与moonbit生态QR包性能对比-方案.md)
- 层②/同尺子：[S9c-性能测试与fast_qr-wasm对比-实现记录.md](./S9c-性能测试与fast_qr-wasm对比-实现记录.md)、
  [S9c-性能测试与fast_qr-wasm对比-详细分析.md](./S9c-性能测试与fast_qr-wasm对比-详细分析.md)
- 优化路线：[S9b-性能优化-评估与路线.md](./S9b-性能优化-评估与路线.md)、
  [S9b-性能优化-O1实施记录.md](./S9b-性能优化-O1实施记录.md)
- 生态包（mooncakes，2026-09-06）：`bobzhang/qrc@0.1.1`、`naoto24kawa/moonqr@0.2.0`、
  `PaiGack/moonbitqrcode@0.1.0`
- 实码：`cmd/bench`（本仓库侧，未改）；仓库外对比模块（本记录 `/tmp/moon-scratch/qrcompare/cmp`）
