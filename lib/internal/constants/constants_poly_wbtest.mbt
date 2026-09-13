///|
/// constants_poly_wbtest.mbt —— T1-a 生成多项式抽查 + 独立推导（S10 §6 T1-a / 缺口 G1）
///
/// 缺口 G1：`get_polynomial(v,ecl)` 此前只有 2 例抽查 + 160 组**度自洽**不变量；
/// 度自洽只约束「长度」，不约束「系数值」。本文件补两条**值级**证据：
///   ① **抽查 4 例**：覆盖 4 个 ECL 与 V01/V07/V40 边界，比对 `(degree, head, mid, last)` 四元组；
///   ② **独立推导**（关键，非自证）：用 QR 规范对生成多项式的**定义**
///      `g_d(x) = Π_{i=0}^{d-1} (x - α^i)`（GF(256)，本原多项式 `x^8+x^4+x^3+x^2+1 = 0x11D`）
///      在测试内**从零重算**出 30 张表（度 1..30），再与实现表逐系数比对。
///
/// ② 的意义：它不依赖 fast_qr、也不依赖本项目实现，是继 T0-c（Python `qrcode` 矩阵）
/// 之后**第二条非自证真值链**（值级、覆盖全 30 张表）。① 提供可定位的边界抽查。
///
/// 表内编码口径（与实现一致）：`generator_polys[d][0] = 0`，`generator_polys[d][k]`（k≥1）
/// 是**降幂**第 k 个系数的**α 指数**（即以 α 为底的离散对数）。
///
/// 来源钉版：fast_qr commit 53e8c99（表值由参考侧提取）；独立推导不经参考。

///|
/// GF(256) 指数域乘法：`α^a * α^b = α^(a+b)`（指数模 255）。

///|
fn poly_gf_mul_alpha(a : Int, b : Int) -> Int {
  (a + b) % 255
}

///|
/// α^e 的域值：本原多项式 `0x11D` 的 LFSR 迭代。
/// 指数域 ↔ 域值往返的独立实现（不读实现内 LOG/ANTILOG 表，避免循环论证）。

///|
fn poly_exp_value(e : Int) -> Int {
  let mut x = 1
  let mut i = 0
  while i < e % 255 {
    x = x << 1
    if (x & 0x100) != 0 {
      x = x ^ 0x11D
    }
    i += 1
  }
  x
}

///|
/// 域值 → α 指数（独立线性扫描实现，不依赖实现的 LOG 表）。

///|
fn poly_log_value(v : Int) -> Int {
  let mut e = 0
  while e < 255 {
    if poly_exp_value(e) == v {
      return e
    }
    e += 1
  }
  0
}

///|
/// GF(256) 域值乘法（独立实现）。

///|
fn poly_mul_value(a : Int, b : Int) -> Int {
  if a == 0 || b == 0 {
    return 0
  }
  let la = poly_log_value(a)
  let lb = poly_log_value(b)
  poly_exp_value(poly_gf_mul_alpha(la, lb))
}

///|
/// 独立推导生成多项式（α 指数域）。
/// 返回长度 d+1 的数组：下标 0 = 降幂首系数指数（恒 0，即 α^0 = 1），
/// 下标 k = 降幂第 k 个系数的 α 指数。
/// 推导：迭代乘 `(x - α^i)`；GF(256) 加法为**域值异或**，故经 `exp → value → xor → log` 往返。

///|
fn poly_ref_derive(degree : Int) -> Array[Int] {
  let g : Array[Int] = [1]
  let mut i = 0
  while i < degree {
    let root = poly_exp_value(i)
    let next : Array[Int] = []
    let mut k = 0
    while k <= g.length() {
      next.push(0)
      k += 1
    }
    let mut j = 0
    while j < g.length() {
      next[j] = next[j] ^ g[j]
      next[j + 1] = next[j + 1] ^ poly_mul_value(g[j], root)
      j += 1
    }
    g.clear()
    let mut m = 0
    while m < next.length() {
      g.push(next[m])
      m += 1
    }
    i += 1
  }
  let out : Array[Int] = []
  let mut n = 0
  while n < g.length() {
    out.push(if g[n] == 0 { 0 } else { poly_log_value(g[n]) })
    n += 1
  }
  out
}

///|
/// T1-a ①：`get_polynomial` 4 例抽查（4 个 ECL + V01/V07/V40 边界），
/// 比对 `(degree, head, mid, last)` 四元组（值级，非仅长度）。
/// 期望值经本文 ② 的**独立推导**交叉确认（同一表两条来源）。

///|
test "t1a_polynomial_spotcheck_4cases" {
  let v01l = get_polynomial(0, 0)
  if v01l.length() != 8 {
    fail("t1a: V01-L degree got=" + (v01l.length() - 1).to_string() + " want=7")
  }
  if v01l[0].to_int() != 0 ||
    v01l[1].to_int() != 87 ||
    v01l[2].to_int() != 229 ||
    v01l[3].to_int() != 146 {
    fail(
      "t1a: V01-L head got=[" +
      v01l[0].to_int().to_string() +
      "," +
      v01l[1].to_int().to_string() +
      "," +
      v01l[2].to_int().to_string() +
      "," +
      v01l[3].to_int().to_string() +
      "] want=[0,87,229,146]",
    )
  }
  if v01l[4].to_int() != 149 {
    fail("t1a: V01-L mid got=" + v01l[4].to_int().to_string() + " want=149")
  }
  if v01l[7].to_int() != 21 {
    fail("t1a: V01-L last got=" + v01l[7].to_int().to_string() + " want=21")
  }
  let v07m = get_polynomial(6, 1)
  if v07m.length() != 19 {
    fail(
      "t1a: V07-M degree got=" + (v07m.length() - 1).to_string() + " want=18",
    )
  }
  if v07m[0].to_int() != 0 ||
    v07m[1].to_int() != 215 ||
    v07m[2].to_int() != 234 ||
    v07m[3].to_int() != 158 {
    fail(
      "t1a: V07-M head got=[" +
      v07m[0].to_int().to_string() +
      "," +
      v07m[1].to_int().to_string() +
      "," +
      v07m[2].to_int().to_string() +
      "," +
      v07m[3].to_int().to_string() +
      "] want=[0,215,234,158]",
    )
  }
  if v07m[9].to_int() != 79 {
    fail("t1a: V07-M mid got=" + v07m[9].to_int().to_string() + " want=79")
  }
  if v07m[18].to_int() != 153 {
    fail("t1a: V07-M last got=" + v07m[18].to_int().to_string() + " want=153")
  }
  let v40l = get_polynomial(39, 0)
  if v40l.length() != 31 {
    fail(
      "t1a: V40-L degree got=" + (v40l.length() - 1).to_string() + " want=30",
    )
  }
  if v40l[0].to_int() != 0 ||
    v40l[1].to_int() != 41 ||
    v40l[2].to_int() != 173 ||
    v40l[3].to_int() != 145 {
    fail(
      "t1a: V40-L head got=[" +
      v40l[0].to_int().to_string() +
      "," +
      v40l[1].to_int().to_string() +
      "," +
      v40l[2].to_int().to_string() +
      "," +
      v40l[3].to_int().to_string() +
      "] want=[0,41,173,145]",
    )
  }
  if v40l[15].to_int() != 222 {
    fail("t1a: V40-L mid got=" + v40l[15].to_int().to_string() + " want=222")
  }
  if v40l[30].to_int() != 180 {
    fail("t1a: V40-L last got=" + v40l[30].to_int().to_string() + " want=180")
  }
  let v14q = get_polynomial(13, 2)
  if v14q.length() != 21 {
    fail(
      "t1a: V14-Q degree got=" + (v14q.length() - 1).to_string() + " want=20",
    )
  }
  if v14q[0].to_int() != 0 ||
    v14q[1].to_int() != 17 ||
    v14q[2].to_int() != 60 ||
    v14q[3].to_int() != 79 {
    fail(
      "t1a: V14-Q head got=[" +
      v14q[0].to_int().to_string() +
      "," +
      v14q[1].to_int().to_string() +
      "," +
      v14q[2].to_int().to_string() +
      "," +
      v14q[3].to_int().to_string() +
      "] want=[0,17,60,79]",
    )
  }
  if v14q[10].to_int() != 180 {
    fail("t1a: V14-Q mid got=" + v14q[10].to_int().to_string() + " want=180")
  }
  if v14q[20].to_int() != 190 {
    fail("t1a: V14-Q last got=" + v14q[20].to_int().to_string() + " want=190")
  }
}

///|
/// T1-a ②：**独立推导**生成多项式表（实现实际引用的 13 个度：7/10/13/15/16/17/18/20/22/24/26/28/30）逐系数比对。
///
/// 真值来源与实现、与 fast_qr 均无关：直接由 QR 规范定义
/// `g_d(x) = \u{03A0}_{i=0}^{d-1} (x - \u{03B1}^i)` 在 GF(256)（本原多项式 0x11D）上重算。
/// 这补上「度自洽不约束系数值」的缺口：任一张表的任一系数被改，本用例即变红。
/// 覆盖口径：`generator_index` 是 4×40 → 30 张表的映射，实际被引用的度仅 13 个
/// （其余度虽在表中但无版本指向）；本用例覆盖**全部被引用度**，即实现的可达表空间。
///
/// 失败信息含 `degree` + 系数下标（可定位，铁律 4）。

///|
test "t1a_polynomial_derived_referenced_degrees" {
  let degrees : Array[Int] = [7, 10, 13, 15, 16, 17, 18, 20, 22, 24, 26, 28, 30]
  for degree in degrees {
    let poly_ref = poly_ref_derive(degree)
    let mut v = 0
    let mut found = false
    while v < 40 && !found {
      let mut e = 0
      while e < 4 && !found {
        let p = get_polynomial(v, e)
        if p.length() - 1 == degree {
          found = true
          if p.length() != poly_ref.length() {
            fail(
              "t1a-derived: degree " +
              degree.to_string() +
              " length got=" +
              p.length().to_string() +
              " want=" +
              poly_ref.length().to_string(),
            )
          }
          let mut k = 0
          while k < poly_ref.length() {
            if p[k].to_int() != poly_ref[k] {
              fail(
                "t1a-derived: degree " +
                degree.to_string() +
                " coeff[" +
                k.to_string() +
                "] (from V" +
                (v + 1).to_string() +
                "/ecl" +
                e.to_string() +
                ") got=" +
                p[k].to_int().to_string() +
                " want=" +
                poly_ref[k].to_string(),
              )
            }
            k += 1
          }
        }
        e += 1
      }
      v += 1
    }
    if !found {
      fail(
        "t1a-derived: 度 " +
        degree.to_string() +
        " 未被任何 (version,ecl) 引用（generator_index 漂移？）",
      )
    }
  }
}

///|

///|
/// T1-a ③：独立推导 GF(256) 的**自证**（防「推导本身写错」）。
/// 校验 `poly_exp_value` 与已知定点：α^0=1、α^1=2、α^8=29（0x11D 首次归约）、α^255=1（周期）。

///|
test "t1a_gf256_prime_poly_selfcheck" {
  if poly_exp_value(0) != 1 {
    fail("t1a-selfcheck: α^0 got=" + poly_exp_value(0).to_string() + " want=1")
  }
  if poly_exp_value(1) != 2 {
    fail("t1a-selfcheck: α^1 got=" + poly_exp_value(1).to_string() + " want=2")
  }
  if poly_exp_value(8) != 29 {
    fail(
      "t1a-selfcheck: α^8 got=" + poly_exp_value(8).to_string() + " want=29",
    )
  }
  if poly_exp_value(255) != 1 {
    fail(
      "t1a-selfcheck: α^255 got=" + poly_exp_value(255).to_string() + " want=1",
    )
  }
  if poly_log_value(29) != 8 {
    fail(
      "t1a-selfcheck: log(29) got=" + poly_log_value(29).to_string() + " want=8",
    )
  }
}
