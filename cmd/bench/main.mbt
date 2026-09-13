///|
/// cmd/bench —— S9 性能三基准点基准命令（V03H / V10H / V40H）
///
/// 用途：复刻参考库 fast_qr v0.14.0 的 criterion 三基准点（输入固定 `https://example.com/`，
///       20 字节，ECL=H，强制版本 V03/V10/V40，mask 留 None 走自动择优），在本仓库跑出可复跑
///       基准数字。对应方案 docs/S9-性能基准.md 实现方案 §4 #1 与
///       docs/S9-性能基准.md 实现记录 §2.3/§3（评估补强）。
///
/// 计时口径（D15）：本命令**内部不内置纳秒钟**（跨后端 host 计时更一致），只稳定地跑完指定点
///       N 次 build 并产出可观测校验总量；真正耗时由宿主 `scripts/bench.sh` 用 bash `time` 对
///       整程计时、多次 run 取最小值（剔除冷启动，对齐 docs/wasm §5.2）。命令产出：
///       - 每点的 `ok=<N> builds, checksum=<int>`（消费每次 build 结果，防死代码消除/空循环）
///       - 末尾 `TOTAL_CHECKSUM=<int>`（跨后端/跨运行结果互证的观测指纹）
///
/// 防死代码消除（评估 §2.3/§3 #2）：循环**必须消费每次 build 的 Result**——把每次成功构建的
///       QRCode 的 `size` 与代表性模块字节、mask/mode/ecl/version 序号累加进校验和，循环外只
///       输出一次总量。否则「只计时不计输出」有被编译器判为无副作用而整段优化掉 / 摊薄成
///       空循环的风险，导致测到的是近乎空循环而非真实 QR 成本。
///
/// 用法（argv 自 cmd/bench 程序路径后起）：
///   moon run cmd/bench --release --            # 跑全部三点（每点默认迭代档）
///   moon run cmd/bench --release -- V40        # 只跑 V40H，默认迭代档
///   moon run cmd/bench --release -- V40 40     # 只跑 V40H，40 次
///   moon run cmd/bench --release -- --dump V40 # 只导出 V40H 值全集规范矩阵（层②逐位对齐用，不计时）
///   moon run cmd/bench --release -- --dump-case list          # 只列 T3-d 多内容语料清单
///   moon run cmd/bench --release -- --dump-case 7             # 只导出第 7 号语料矩阵（0 基）
///   moon run cmd/bench --release -- --dump-case all           # 导出全部语料矩阵（供解码回读批量审计）
/// 版本越大单次越贵、默认迭代越少（避免单点 <1ms 计时噪声）。host 侧 scripts/bench.sh 用
/// 「多次取最小」为每点×后端分别计时。
///
/// --dump 说明（S9c D19）：层②「与 fast_qr wasm 逐位对齐」需要**值全集（0/1）规范矩阵**——现默认
/// 校验和取样走 Module::byte()（含模块类型位 bit1-3），fast_qr wasm 侧只输出 0/1 明暗值，两套公式
/// 不可跨库互比。--dump 一次 build 后逐行导出 '0'/'1'（行主序，值=模块明暗），供 Node 宿主与 fast_qr
/// wasm 产物 diff/sha256；默认路径行为完全不变（层①数字可复现）。
///
/// KEEP_LAST 说明（评估 §2.4）：真实 QR 路径单次 push ≤16 位、index>16 不触达，故本仓库 wasm
///       形态（KEEP_LAST=33）与 fast_qr native（=65）对 V03H/V10H/V40H 矩阵输出语义一致；层②对
///       fast_qr-wasm32 逐位对齐预期必然通过，其增量价值主要在「同执行模型计时」。
/// 对应参考：fast_qr v0.14.0 `benches/qr.rs`（V03H/V10H/V40H、输入 `https://example.com/`）。

///|
/// 基准输入（fast_qr 三基准点共用）。逐字符 `https://example.com/` 恰为 **20 字节**。
/// 语义：Byte-H 容量 V02H=14 < 20 ≤ V03H=24 → V03H 为 20 字节的最小适配版本（强制写 .version
///       V03 与参考「指定版本」路径同构）；V10H=119、V40H=1273 富余，靠强制版本体现大矩阵成本。
fn bench_input() -> String {
  "https://example.com/"
}

///|
/// 某版本的默认迭代数（按参考耗时量级粗配：版本越大单次越贵、迭代越少，避免计时噪声）。
fn default_iters(ver : @lib.Version) -> Int {
  match ver {
    V03 => 2000
    V10 => 400
    _ => 40
  }
}

///|
/// 版本 → 可读名（V03H/V10H/V40H）。
fn point_name(ver : @lib.Version) -> String {
  match ver {
    V03 => "V03H"
    V10 => "V10H"
    _ => "V40H"
  }
}

///|
/// 由用户传入的版本选择串解析为版本；无法识别回退 `None`。
fn parse_point(s : String) -> @lib.Version? {
  match s {
    "V03" => Some(@lib.Version::V03)
    "V10" => Some(@lib.Version::V10)
    "V40" => Some(@lib.Version::V40)
    _ => None
  }
}

///|
/// 安全解析非负整数迭代数：缺省 / 非法 → 0（由调用方回退默认档）。
fn parse_iters_opt(s : String) -> Int {
  try {
    let v = @string.parse_int(s)
    if v >= 0 {
      v
    } else {
      0
    }
  } catch {
    _ => 0
  }
}

///|
/// 单点跑 N 次 build 的校验和（**消费每次 Result**，防死代码消除）。读 size + 少量代表性
/// 模块字节 + 元数据序号进指纹：既依赖真实 build 输出、又开销极小，不显著污染被测路径耗时。
/// 固定版本 + ecl H 绝不会 Err（容量富余），显式兜底以防门禁 unused_result。
fn bench_point_checksum(ver : @lib.Version, n : Int) -> Int {
  let mut ok_count = 0
  let mut checksum = 0
  let mut i = 0
  while i < n {
    let res = @lib.QRBuilder::from_string(bench_input())
      .ecl(@lib.ECL::H)
      .version(ver)
      .build()
    match res {
      Ok(q) => {
        ok_count = ok_count + 1
        checksum = checksum + q.size()
        checksum = checksum + q.get(0, 0).byte().to_int()
        let sz = q.size()
        checksum = checksum + q.get(sz - 1, sz - 1).byte().to_int()
        checksum = checksum + q.get(sz / 2, sz / 2).byte().to_int()
        // 自动择优后实际选中的元数据序号
        match q.mask() {
          Some(m) => checksum = checksum + m.to_int()
          None => ()
        }
        match q.mode() {
          Some(m) => checksum = checksum + m.to_int()
          None => ()
        }
        match q.ecl() {
          Some(e) => checksum = checksum + e.to_int()
          None => ()
        }
        match q.version() {
          Some(v) => checksum = checksum + v.to_int()
          None => ()
        }
      }
      Err(_) =>
        abort(
          "bench: force-version build unexpectedly failed for \{point_name(ver)}",
        )
    }
    i = i + 1
  }
  checksum
}

///|
/// 值全集规范矩阵导出（S9c D19，层②逐位对齐协议）。对指定点 build **一次**并导出：
///   首行 `QR_MATRIX <点名> size=<边长>`，随后 `size` 行、每行 `size` 个 '1'/'0'
///   （行主序；1=DARK/0=LIGHT，即 `Module::value()`，不含模块类型位——fast_qr wasm 侧
///   `bool_to_u8` 只取该位，故本协议两侧可逐字符 diff）。
/// 输出全部经 println 落地，build 结果被消费，无死代码消除风险。
fn dump_matrix(ver : @lib.Version) -> Unit {
  let res = @lib.QRBuilder::from_string(bench_input())
    .ecl(@lib.ECL::H)
    .version(ver)
    .build()
  match res {
    Ok(q) => {
      let size = q.size()
      println("QR_MATRIX \{point_name(ver)} size=\{size}")
      let mut row = 0
      while row < size {
        let sb = StringBuilder()
        let mut col = 0
        while col < size {
          if q.get(row, col).value() {
            sb.write_char('1')
          } else {
            sb.write_char('0')
          }
          col += 1
        }
        println(sb.to_string())
        row += 1
      }
    }
    Err(_) =>
      abort(
        "bench: force-version build unexpectedly failed for \{point_name(ver)}",
      )
  }
}

///|
/// 跑单个版本 `n` 次并打印一行；返回其校验和。
fn run_one(ver : @lib.Version, n : Int) -> Int {
  let cs = bench_point_checksum(ver, n)
  println("\{point_name(ver)}: \{n} builds, checksum=\{cs}")
  cs
}

///|
/// 三版本各自跑默认迭代档（host 无版本选择时的一键全跑 / CI 冒烟）。
fn run_all_default() -> Int {
  let versions : Array[@lib.Version] = [
    @lib.Version::V03,
    @lib.Version::V10,
    @lib.Version::V40,
  ]
  let mut total = 0
  for ver in versions {
    total = total + run_one(ver, default_iters(ver))
  }
  total
}

///|
/// T3-d 多内容探针语料：三模式 × 4 ECL × {V01,V05,V10,V40} = **20 组**（验收要求 ≥12 组）。
/// 每组固定 `(模式, ECL, 版本, 内容)` 四元组；内容取该组合下的**代表性长度**
/// （Numeric 数字串 / Alphanumeric 大写串 / Byte 小写串），确保非全 None 自动路径、
/// 且长度落在该版本容量内（否则 build 会 Err，探针直接 abort 报错便于定位）。
/// 语义：本表是**只读探针语料**，不参与计时、不写文件、无 argv 副作用。
/// `version = None` 表示**不强制版本**（走 `select_capacity` 按模式求最小适配版本）。
/// 这类 case 是 v5 修复的**靶点**：旧实现在 `version=None` 时按 Numeric 预算选版本，
/// 会把长 Byte 串写进装不下它的数据区（实测矩阵交给 jsQR 解码返回 NULL，见 S10 附录 H）。
/// `version = Some(v)` 表示强制版本（覆盖 `SpecifiedVersion` 错误面与跨 CCI 档判定）。
struct T3dCase {
  mode : @lib.Mode
  ecl : @lib.ECL
  version : @lib.Version?
  content : String
  /// 语料用途标记（`grid` = 三模式×4ECL×4版本网格；`auto` = 自动版本靶点）
  kind : String
}

///|
/// 语料表（20 组，见 S10 T3-d 验收口径）。
fn t3d_cases() -> Array[T3dCase] {
  let out : Array[T3dCase] = []
  let modes : Array[@lib.Mode] = [
    @lib.Mode::Numeric,
    @lib.Mode::Alphanumeric,
    @lib.Mode::Byte,
  ]
  let ecls : Array[@lib.ECL] = [
    @lib.ECL::L,
    @lib.ECL::M,
    @lib.ECL::Q,
    @lib.ECL::H,
  ]
  let vers : Array[@lib.Version] = [
    @lib.Version::V01,
    @lib.Version::V05,
    @lib.Version::V10,
    @lib.Version::V40,
  ]
  for mode in modes {
    for ecl in ecls {
      for ver in vers {
        // 内容长度按 (模式, 版本) 取：**必须 <= 该版本下最弱 ECL（H）的容量**，
        // 否则高 ECL 组合会 build 失败（探针语料须全部可构建）。
        // 真值取自容量表：V01-H → Numeric 17 / Alnum 10 / Byte 7；V05-H → 106/64/44；
        // V10-H → 288/174/119；V40-H → 3057/1852/1273。这里取各档的**安全下界**。
        let n = match (mode, ver) {
          (Numeric, V01) => 16
          (Numeric, V05) => 100
          (Numeric, V10) => 280
          (Numeric, _) => 1200
          (Alphanumeric, V01) => 9
          (Alphanumeric, V05) => 60
          (Alphanumeric, V10) => 170
          (Alphanumeric, _) => 1000
          (Byte, V01) => 6
          (Byte, V05) => 40
          (Byte, V10) => 110
          (Byte, _) => 800
        }
        let content = match mode {
          Numeric => t3d_repeat('9', n)
          Alphanumeric => t3d_repeat('A', n)
          Byte => t3d_repeat('z', n)
        }
        out.push(T3dCase::{
          mode,
          ecl,
          version: Some(ver),
          content,
          kind: "grid",
        })
      }
    }
  }
  // ── 自动版本靶点（`version=None`）────────────────────────────────────────
  // 旧实现在此按 Numeric 预算选版本：Byte-40 + ECL H 会被选到 V03-H（数据区仅 26 字节），
  // 而 Byte 编码实际需 42 字节 → 后 16 字节被丢弃，矩阵**不可解码**（jsQR 返回 NULL）。
  // 覆盖三模式 × {H,Q}（H 容量最小、最易暴露），共 6 组。
  let autos : Array[(@lib.Mode, @lib.ECL, String)] = [
    (@lib.Mode::Numeric, @lib.ECL::H, t3d_repeat('9', 40)),
    (@lib.Mode::Numeric, @lib.ECL::Q, t3d_repeat('9', 40)),
    (@lib.Mode::Alphanumeric, @lib.ECL::H, t3d_repeat('A', 40)),
    (@lib.Mode::Alphanumeric, @lib.ECL::Q, t3d_repeat('A', 40)),
    (@lib.Mode::Byte, @lib.ECL::H, t3d_repeat('z', 40)),
    (@lib.Mode::Byte, @lib.ECL::Q, t3d_repeat('z', 40)),
  ]
  for (mode, e, content) in autos {
    out.push(T3dCase::{ mode, ecl: e, version: None, content, kind: "auto", })
  }
  out
}

///|
/// 重复字符 `n` 次（探针语料构造辅助；不引入额外 core 依赖）。
fn t3d_repeat(ch : Char, n : Int) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < n {
    sb.write_char(ch)
    i += 1
  }
  sb.to_string()
}

///|
/// 模式/ECL/版本的短名（`QR_CASE` 元数据行与 `QR_MATRIX` label 用）。
fn t3d_mode_name(m : @lib.Mode) -> String {
  match m {
    Numeric => "Numeric"
    Alphanumeric => "Alphanumeric"
    Byte => "Byte"
  }
}

///|
fn t3d_ecl_name(e : @lib.ECL) -> String {
  match e {
    L => "L"
    M => "M"
    Q => "Q"
    H => "H"
  }
}

///|
fn t3d_version_name(v : @lib.Version) -> String {
  "V\{v.to_int() + 1}"
}

///|
/// 导出单组语料矩阵：首行 `QR_CASE index=… mode=… ecl=… version=… size=… content_len=…`
/// 元数据行（供第三方解码脚本核对口径），随后 `QR_MATRIX <label> size=<n>` + n 行 0/1，
/// 与既有 `--dump` 协议**完全一致**（同一 consumer 可复用）。
fn dump_t3d_case(index : Int) -> Unit {
  let cases = t3d_cases()
  // 注意：MoonBit 里 `a >= 0 && a < n` **不能按 C 直觉解析**，必须显式加括号。
  if !(index >= 0 && index < cases.length()) {
    println("QR_CASE_ERROR index=\{index} out_of_range total=\{cases.length()}")
    return
  }
  let c = cases[index]
  let input : Array[Byte] = []
  for ch in c.content {
    input.push(ch.to_int().to_byte())
  }
  let builder = @lib.QRBuilder::from_string(c.content).mode(c.mode).ecl(c.ecl)
  let res = match c.version {
    Some(v) => builder.version(v).build()
    None => builder.build()
  }
  match res {
    Ok(q) => {
      let size = q.size()
      let vname = match c.version {
        Some(v) => t3d_version_name(v)
        None => "auto"
      }
      let label = "\{t3d_mode_name(c.mode)}-\{t3d_ecl_name(c.ecl)}-\{vname}"
      println(
        "QR_CASE index=\{index} kind=\{c.kind} mode=\{t3d_mode_name(c.mode)} ecl=\{t3d_ecl_name(c.ecl)} version=\{vname} size=\{size} content_len=\{input.length()}",
      )
      println("QR_MATRIX \{label} size=\{size}")
      let mut row = 0
      while row < size {
        let sb = StringBuilder()
        let mut col = 0
        while col < size {
          if q.get(row, col).value() {
            sb.write_char('1')
          } else {
            sb.write_char('0')
          }
          col += 1
        }
        println(sb.to_string())
        row += 1
      }
    }
    Err(_) =>
      // 显式 Err → 打印可定位的错误行并退出（探针语料必须全部可构建）
      println(
        "QR_CASE_ERROR index=\{index} kind=\{c.kind} build_failed mode=\{t3d_mode_name(c.mode)} ecl=\{t3d_ecl_name(c.ecl)}",
      )
  }
}

///|
/// 只列语料清单（不构建矩阵）：一行一组的 `QR_CASE_LIST index=… mode=… ecl=… version=… content_len=…`。
fn list_t3d_cases() -> Unit {
  let cases = t3d_cases()
  let mut i = 0
  while i < cases.length() {
    let c = cases[i]
    let vname = match c.version {
      Some(v) => t3d_version_name(v)
      None => "auto"
    }
    println(
      "QR_CASE_LIST index=\{i} kind=\{c.kind} mode=\{t3d_mode_name(c.mode)} ecl=\{t3d_ecl_name(c.ecl)} version=\{vname} content_len=\{c.content.length()}",
    )
    i += 1
  }
  println("QR_CASE_TOTAL=\{cases.length()}")
}

///|
/// 解析 `--dump-case` 实参：`all` / `list` / 非负整数。
enum T3dArg {
  All
  List
  One(Int)
  Bad(String)
}

///|
fn parse_t3d_arg(s : String) -> T3dArg {
  if s == "all" {
    All
  } else if s == "list" {
    List
  } else {
    try {
      let v = @string.parse_int(s)
      if v >= 0 {
        One(v)
      } else {
        Bad(s)
      }
    } catch {
      _ => Bad(s)
    }
  }
}

///|
/// 运行 `--dump-case` 子命令。
fn run_dump_case(s : String) -> Unit {
  match parse_t3d_arg(s) {
    List => list_t3d_cases()
    One(i) => dump_t3d_case(i)
    All => {
      let cases = t3d_cases()
      let mut i = 0
      while i < cases.length() {
        dump_t3d_case(i)
        i += 1
      }
    }
    Bad(s) =>
      // 注：`abort` 的字符串在**常量折叠**阶段就会求值，故这里用 println + return，
      // 避免 `s` 只是运行期值却在编译期被求值（实测踩过：命令一启动就 abort）。
      println("--dump-case expects all|list|<non-negative int>, got: \{s}")
  }
}

///|
fn main {
  let argv = @env.args()
  // argv[0] = 程序/产物路径；argv[1]（可选）= 版本选择 或 `--dump`；argv[2]（可选）= 迭代数 /
  // `--dump` 时的版本选择。
  if argv.length() > 1 && argv[1] == "--dump-case" {
    let arg = if argv.length() > 2 { argv[2] } else { "list" }
    run_dump_case(arg)
  } else if argv.length() > 1 && argv[1] == "--dump" {
    let ver_opt = if argv.length() > 2 { parse_point(argv[2]) } else { None }
    match ver_opt {
      Some(ver) => dump_matrix(ver)
      None => println("--dump expects V03|V10|V40")
    }
  } else {
    let total = match argv.length() {
      0 | 1 => run_all_default()
      _ => {
        let ver_opt = parse_point(argv[1])
        match ver_opt {
          Some(ver) => {
            let n = if argv.length() > 2 {
              let ov = parse_iters_opt(argv[2])
              if ov > 0 {
                ov
              } else {
                default_iters(ver)
              }
            } else {
              default_iters(ver)
            }
            run_one(ver, n)
          }
          None => {
            println(
              "unknown point '\{argv[1]}'; expected V03|V10|V40|(default all)",
            )
            run_all_default()
          }
        }
      }
    }
    println("TOTAL_CHECKSUM=\{total}")
  }
}
