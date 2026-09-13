// snapshot_gen_score.rs —— 参考侧「打分明细」黄金值发射器（S10 §6 T2-a/T2-b）
// （开发期工具；由 scripts/gen-goldens.sh --emit-score 注入 fast_qr 检出 src/tests/ 后运行）
//
// 用途：把参考 fast_qr v0.14.0 的**逐行/逐列 N1 运行分**与**矩阵级四规则分量**
// 在参考侧实际算出并打印，供 MoonBit 侧逐项断言（铁律 1：参考值禁止手抄）。
//
// 语料：使用参考自带**类型化**夹具 `XIAOJIBA_MOD`（29×29，`Module(n)` 直接是可比的
// packed 值 `明暗|类型<<1`），避免手抄且类型精确。
//
// 输出格式（stdout，以 "GOLDEN|" 前缀，便于 shell 过滤）：
//   GOLDEN|LINE|<label>|<scores_csv>     逐行 N1 运行分（test_score_line）
//   GOLDEN|COL|<label>|<scores_csv>      逐列 N1 运行分
//   GOLDEN|MATRIX|<label>|<squares>|<patt>|<dark>|<line_total>|<col_total>
//   GOLDEN|HEX|<label>|<packed_hex>      矩阵 packed 值（每格 2 位 hex，行主序）
use crate::score::{
    test_matrix_dark_modules, test_matrix_pattern_and_line, test_matrix_score_squares,
    test_score_line,
};
use crate::Module;

fn dump(label: &str, mat: &[[Module; 29]; 29]) {
    let mut rows = Vec::new();
    for i in 0..29 {
        rows.push(test_score_line(&mat[i]));
    }
    println!(
        "GOLDEN|LINE|{}|{}",
        label,
        rows.iter().map(|v| v.to_string()).collect::<Vec<_>>().join(",")
    );
    let mut cols = Vec::new();
    let mut colbuf = [Module::data(false); 29];
    for j in 0..29 {
        for i in 0..29 {
            colbuf[i] = mat[i][j];
        }
        cols.push(test_score_line(&colbuf));
    }
    println!(
        "GOLDEN|COL|{}|{}",
        label,
        cols.iter().map(|v| v.to_string()).collect::<Vec<_>>().join(",")
    );
    // 矩阵级分量：参考 API 需要 &QRCode，这里对 29×29 逐行做等价聚合。
    // squares：照抄参考 matrix_score_squares 逻辑（对同一 packed 值矩阵）；
    // pattern/line：由上面的逐行/逐列 + 参考的 line() 语义组合得出。
    let mut line_total = 0u32;
    let mut col_total = 0u32;
    for v in &rows {
        line_total += v;
    }
    for v in &cols {
        col_total += v;
    }
    // pattern：逐行/逐列 test_score_pattern
    let mut pattern = 0u32;
    for i in 0..29 {
        pattern += crate::score::test_score_pattern(&mat[i]);
    }
    for j in 0..29 {
        let mut cb = [Module::data(false); 29];
        for i in 0..29 {
            cb[i] = mat[i][j];
        }
        pattern += crate::score::test_score_pattern(&cb);
    }
    // squares：参考同构逻辑（此处直接调用参考 test 版本需 QRCode，故内联等价实现）
    let mut square = 0u32;
    for i in 0..28 {
        let mut count_data = 2;
        let mut buffer = 0u8;
        buffer |= u8::from(mat[i][0].value()) << 2;
        buffer |= u8::from(mat[i + 1][0].value()) << 3;
        for j in 0..28 {
            buffer >>= 2;
            buffer |= u8::from(mat[i][j + 1].value()) << 2;
            buffer |= u8::from(mat[i + 1][j + 1].value()) << 3;
            if mat[i][j + 1].module_type() != crate::ModuleType::Data
                || mat[i + 1][j + 1].module_type() != crate::ModuleType::Data
            {
                count_data = 0;
            }
            if count_data >= 2 && (buffer == 0b1111 || buffer == 0b0000) {
                square += 3;
            }
            count_data += 1;
        }
    }
    let mut dark = 0u32;
    for i in 0..29 {
        for j in 0..29 {
            if mat[i][j].value() {
                dark += 1;
            }
        }
    }
    println!(
        "GOLDEN|MATRIX|{}|{}|{}|{}|{}|{}",
        label, square, pattern, dark, line_total, col_total
    );
    let mut hex = String::new();
    for i in 0..29 {
        for j in 0..29 {
            hex.push_str(&format!("{:02x}", mat[i][j].0));
        }
    }
    println!("GOLDEN|HEX|{}|{}", label, hex);
    let _ = (test_matrix_dark_modules, test_matrix_pattern_and_line, test_matrix_score_squares);
}

/// 参考夹具 `XIAOJIBA_MOD`（29×29 类型化矩阵）。为免依赖参考测试模块的可见性，
/// 此处**原样内联**参考 `src/tests/score.rs::XIAOJIBA_MOD` 的 841 个 packed 字节
/// （由参考源码机械转换得到；本文件只在参考检出内运行，产物经人工审阅）。
#[rustfmt::skip]
const XIAOJIBA_MOD_PACKED: [u8; 841] = [3, 3, 3, 3, 3, 3, 3, 14, 8, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 14, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 3, 14, 8, 1, 1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 14, 3, 2, 2, 2, 2, 2, 3, 3, 2, 3, 3, 3, 2, 3, 14, 9, 1, 1, 0, 1, 0, 1, 1, 1, 0, 0, 1, 0, 14, 3, 2, 3, 3, 3, 2, 3, 3, 2, 3, 3, 3, 2, 3, 14, 9, 1, 1, 1, 0, 1, 0, 0, 0, 1, 0, 0, 1, 14, 3, 2, 3, 3, 3, 2, 3, 3, 2, 3, 3, 3, 2, 3, 14, 8, 1, 0, 1, 1, 1, 0, 0, 1, 0, 1, 1, 0, 14, 3, 2, 3, 3, 3, 2, 3, 3, 2, 2, 2, 2, 2, 3, 14, 8, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 14, 3, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 14, 7, 6, 7, 6, 7, 6, 7, 6, 7, 6, 7, 6, 7, 14, 3, 3, 3, 3, 3, 3, 3, 14, 14, 14, 14, 14, 14, 14, 14, 8, 0, 0, 0, 0, 0, 1, 0, 1, 1, 1, 1, 1, 14, 14, 14, 14, 14, 14, 14, 14, 8, 8, 8, 9, 9, 8, 7, 9, 8, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 8, 8, 8, 8, 9, 9, 8, 8, 1, 1, 0, 1, 1, 0, 6, 1, 1, 0, 1, 1, 0, 1, 1, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 1, 0, 0, 1, 7, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1, 6, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 7, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 1, 6, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 1, 7, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 0, 1, 0, 1, 6, 0, 1, 1, 1, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1, 7, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 0, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 0, 1, 0, 6, 0, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 7, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 6, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 7, 1, 1, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 5, 5, 5, 5, 5, 1, 1, 0, 1, 14, 14, 14, 14, 14, 14, 14, 14, 13, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 5, 4, 4, 4, 5, 1, 1, 0, 0, 3, 3, 3, 3, 3, 3, 3, 14, 9, 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1, 5, 4, 5, 4, 5, 0, 1, 0, 0, 3, 2, 2, 2, 2, 2, 3, 14, 8, 1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 1, 5, 4, 4, 4, 5, 1, 0, 1, 0, 3, 2, 3, 3, 3, 2, 3, 14, 9, 1, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 5, 5, 5, 5, 5, 0, 0, 0, 0, 3, 2, 3, 3, 3, 2, 3, 14, 9, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 3, 2, 3, 3, 3, 2, 3, 14, 8, 1, 1, 1, 0, 1, 0, 1, 1, 1, 0, 0, 1, 1, 0, 1, 1, 0, 0, 1, 1, 3, 2, 2, 2, 2, 2, 3, 14, 8, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1, 3, 3, 3, 3, 3, 3, 3, 14, 8, 0, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0];

fn xiaojiba() -> [[Module; 29]; 29] {
    let mut out = [[Module::data(false); 29]; 29];
    for i in 0..29 {
        for j in 0..29 {
            out[i][j] = Module(XIAOJIBA_MOD_PACKED[i * 29 + j]);
        }
    }
    out
}

#[test]
fn __emit_score_goldens() {
    dump("xiaojiba_dev", &xiaojiba());
}
