///|
/// cmd/qr-min —— 纯库调用体积探针（S9i 口径，语义对齐 fast_qr 侧 `s9f_size_probe`）。
///
/// 背景：S9f/S9g 的体积口径只有 `cmd/bench`（argv + 迭代 + `--dump` + checksum 外壳）与
///       `cmd/main`（终端字符画 + SVG 输出层 + 演示外壳）两档可执行包——它们度量的是
///       「命令形态」的产物，**不能代表本库被宿主嵌入时的实际体积**（外壳代码不随库分发）。
///       fast_qr 侧早有核心-only 裸探针（45687 B），MoonBit 侧一直缺同形锚点，
///       导致 ⑤ 同功能锚点对比不对称（MoonBit 侧被外壳高估）。本包补齐这一口径。
///
/// 行为：对三基准点（V03/V10/V40；输入 `https://example.com/`=20B、ECL=H、mask 自动择优）
///       各 build **一次**，把 `size` 与代表性模块字节累加进校验总量，末尾 `println` 一行。
///       结果被真实消费，无死代码消除风险；除 `println`（与 hello 地板同面）外零宿主依赖。
///
/// 用法：`moon run cmd/qr-min`（无参数、不读 argv）。
/// 语义护栏：moonrun（wasm-gc，唯一后端）输出恒为 `QR_MIN_CHECKSUM=283`（跨优化档必须一致）。

///|
/// 三基准点各 build 一次的校验总量（消费每次 Result，防死代码消除；口径同 cmd/bench 单点采样）。
fn probe_checksum() -> Int {
  let versions : Array[@lib.Version] = [
    @lib.Version::V03,
    @lib.Version::V10,
    @lib.Version::V40,
  ]
  let mut checksum = 0
  for ver in versions {
    match
      @lib.QRBuilder::from_string("https://example.com/")
      .ecl(@lib.ECL::H)
      .version(ver)
      .build() {
      Ok(q) => {
        let sz = q.size()
        checksum = checksum + sz
        checksum = checksum + q.get(0, 0).byte().to_int()
        checksum = checksum + q.get(sz - 1, sz - 1).byte().to_int()
        checksum = checksum + q.get(sz / 2, sz / 2).byte().to_int()
      }
      Err(_) => println("qr-min: force-version build unexpectedly failed")
    }
  }
  checksum
}

///|
fn main {
  println("QR_MIN_CHECKSUM=\{probe_checksum()}")
}
