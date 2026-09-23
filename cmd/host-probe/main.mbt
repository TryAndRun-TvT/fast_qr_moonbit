///|
/// cmd/host-probe —— S9p 宿主调用面探针（真实「JS 向 wasm 传参」形态）
///
/// 背景：`cmd/bench` 是**命令形态**（`_start` + argv），输入经 `__moonbit_fs_unstable` 协议
///       在实例创建时注入；Node 侧要「参数化调用」只能：
///       - A 口径：每次新建 Instance 再跑 `_start`（Instance 创建成本被计进每次调用）；
///       - B 口径：把迭代数也塞进 argv，让 wasm 内部紧循环（宿主传参成本被完全抹平）。
///       两者都不是宿主真实调用形态：宿主拿到的是一个**一次实例化、可反复带参调用**的模块。
///
/// 本包按真实集成形态导出：
///   `qr_generate(content : String, version : Int) -> Int`
///     - `content`：**每次调用由宿主直接传的 JS 字符串**（走 JS String Builtins `stringref`）；
///     - `version`：0=V03 / 1=V10 / 2=V40（强制版本，ECL 固定 H，mask 自动择优）；
///     - 返回：与 `cmd/bench` 同公式的**单次调用校验和**（消费 build 结果，防死代码消除）。
///   宿主一次 `WebAssembly.compile(..., {builtins:["js-string"]})` + 一次 Instance，随后在该
///   实例上循环调用 N 次并自行计时——这才是「模拟正常调用 JS 向 wasm 传参」。
///
/// `qr_checksum(version)` 是 A/B 对照：同一 build、但内容由 wasm 侧常量给出，用于把
///   「宿主传字符串参数」的边际成本单独分账（`qr_generate` − `qr_checksum`）。
///
/// 语义护栏：返回值公式与 `cmd/bench::bench_point_checksum` 的单次项**完全一致**，
///   故同一内容/版本下「宿主调用面」与「CLI 面」取值相同（见 scripts/host-bench.mjs 的 ALIGN 护栏）。

///|
/// 基准输入（与 `cmd/bench::bench_input` 同源，保证跨口径可比）。
const HOST_INPUT : String = "https://example.com/"

///|
/// 版本选择号 → 强制版本；越界回退 V03。
fn host_version(sel : Int) -> @lib.Version {
  match sel {
    1 => V10
    2 => V40
    _ => V03
  }
}

///|
/// 单次调用校验和（公式与 `cmd/bench::bench_point_checksum` 的单次项**完全一致**）：
/// `size + get(0,0) + get(sz-1,sz-1) + get(sz/2,sz/2) + mask + mode + ecl + version`。
/// 与 cmd/bench 同式即可让 JS 宿主与 CLI 两个口径在同一参数下互相验证。
fn host_checksum(content : String, ver : @lib.Version) -> Int {
  match @lib.QRBuilder::from_string(content).ecl(H).version(ver).build() {
    Ok(q) => {
      let sz = q.size()
      let mut cs = sz
      cs = cs + q.get(0, 0).byte().to_int()
      cs = cs + q.get(sz - 1, sz - 1).byte().to_int()
      cs = cs + q.get(sz / 2, sz / 2).byte().to_int()
      match q.mask() {
        Some(m) => cs = cs + m.to_int()
        None => ()
      }
      match q.mode() {
        Some(m) => cs = cs + m.to_int()
        None => ()
      }
      match q.ecl() {
        Some(e) => cs = cs + e.to_int()
        None => ()
      }
      match q.version() {
        Some(v) => cs = cs + v.to_int()
        None => ()
      }
      cs
    }
    Err(_) => -1
  }
}

///|
/// 宿主调用面 #1：`(content, version) -> checksum`。宿主在同一实例上反复带参调用。
pub fn qr_generate(content : String, ver_sel : Int) -> Int {
  host_checksum(content, host_version(ver_sel))
}

///|
/// 宿主调用面 #2：`(version) -> checksum`，内容由 wasm 侧常量给出（不传字符串）。
/// 用途：把「宿主传字符串参数」的成本单独分账（`qr_generate` − `qr_checksum`）。
/// 两者都会真实走完整 build 路径，不是绕过护栏。
pub fn qr_checksum(ver_sel : Int) -> Int {
  host_checksum(HOST_INPUT, host_version(ver_sel))
}
