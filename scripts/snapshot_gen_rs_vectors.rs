// snapshot_gen_rs_vectors.rs —— 参考侧 division/structure 黄金向量发射器
// （开发期工具；由 scripts/gen-goldens.sh 注入 fast_qr 检出 src/tests/ 后运行，不入本仓库）
//
// 用途（S10 §6 T1-c/T1-d）：在 fast_qr v0.14.0 检出内**实际计算** GF(256) 除法余数与
// 交织结果，供 MoonBit 侧逐字节对齐（铁律 1：参考值禁止手抄，一律由脚本产出）。
//
// 输出格式（stdout，以 "GOLDEN|" 前缀，便于 shell 过滤）：
//   GOLDEN|DIV|<label>|<gen_len>|<rem_hex>
//   GOLDEN|STRUCT|<label>|<ecl>|<version>|<data_hex>|<out_hex>
//
// 注入方式见 scripts/gen-goldens.sh（自动追加到 src/tests/mod.rs）。
use crate::polynomials;
use crate::{ECL, Version};

fn hex(data: &[u8]) -> String {
    data.iter().map(|b| format!("{:02x}", b)).collect()
}

/// 参考 error_correction.rs 的 8 组输入（含 gen 由 get_polynomial 决定）。
#[test]
fn __emit_goldens() {
    // --- T1-c：division 余数（8 组，直接对齐参考 error_correction.rs） ---
    let div_cases: [(&str, Version, ECL, &[u8]); 8] = [
        (
            "v05q_01",
            Version::V05,
            ECL::Q,
            &[67, 85, 70, 134, 87, 38, 85, 194, 119, 50, 6, 18, 6, 103, 38],
        ),
        (
            "v05q_02",
            Version::V05,
            ECL::Q,
            &[246, 246, 66, 7, 118, 134, 242, 7, 38, 86, 22, 198, 199, 146, 6],
        ),
        (
            "v05q_03",
            Version::V05,
            ECL::Q,
            &[182, 230, 247, 119, 50, 7, 118, 134, 87, 38, 82, 6, 134, 151, 50, 7],
        ),
        (
            "v05q_04",
            Version::V05,
            ECL::Q,
            &[70, 247, 118, 86, 194, 6, 151, 50, 16, 236, 17, 236, 17, 236, 17, 236],
        ),
        (
            "struct_31_0",
            Version::V05,
            ECL::Q,
            &[28, 195, 100, 36, 175, 11, 35, 243, 28, 137, 59, 182, 193],
        ),
        (
            "struct_31_1",
            Version::V05,
            ECL::Q,
            &[35, 37, 251, 189, 8, 169, 15, 34, 59, 137, 187, 114, 134],
        ),
        ("small_1", Version::V01, ECL::L, &[32, 9]),
        ("custom_22_30", Version::V05, ECL::Q, &[
            29, 10, 145, 40, 0, 90, 126, 137, 221, 186, 137, 39, 208, 250, 199, 176, 202, 124, 200,
            85, 63, 254,
        ]),
    ];
    for (label, ver, ecl, data) in div_cases.iter() {
        let gen = crate::hardcode::get_polynomial(*ver, *ecl);
        let (d, g) = if *label == "custom_22_30" {
            // 该参考用例用自定义 by（30 字节），此处按参考 error_correction.rs 直接给定
            (
                data.to_vec(),
                vec![
                    0u8, 156, 45, 183, 29, 151, 219, 54, 96, 249, 24, 136, 5, 241, 175, 189, 28,
                    75, 234, 150, 148, 23, 9, 202, 162, 68, 250, 140, 24, 151,
                ],
            )
        } else {
            (data.to_vec(), gen.to_vec())
        };
        let out = polynomials::division(&d, &g);
        let rem = &out[256 - g.len()..255];
        println!("GOLDEN|DIV|{}|{}|{}", label, g.len(), hex(rem));
    }

    // --- T1-d：structure 交织（V05-Q 输入，消息区 + 纠错区整段） ---
    let data: Vec<u8> = vec![
        67, 85, 70, 134, 87, 38, 85, 194, 119, 50, 6, 18, 6, 103, 38, 246, 246, 66, 7, 118, 134,
        242, 7, 38, 86, 22, 198, 199, 146, 6, 182, 230, 247, 119, 50, 7, 118, 134, 87, 38, 82, 6,
        134, 151, 50, 7, 70, 247, 118, 86, 194, 6, 151, 50, 16, 236, 17, 236, 17, 236, 17, 236,
    ];
    let out = polynomials::structure(&data, ECL::Q, Version::V05);
    let max = Version::V05.max_bytes();
    println!(
        "GOLDEN|STRUCT|v05q|2|4|{}|{}",
        hex(&data),
        hex(&out[..max])
    );

    // --- T1-d 扩样：V10-Q / V07-H / V16-M / V03-Q（确定性 LCG 生成输入，避免手抄） ---
    let extra: [(&str, Version, ECL); 4] = [
        ("v10q", Version::V10, ECL::Q),
        ("v07h", Version::V07, ECL::H),
        ("v16m", Version::V16, ECL::M),
        ("v03q", Version::V03, ECL::Q),
    ];
    for (label, ver, ecl) in extra.iter() {
        let n = crate::hardcode::data_codewords(*ver, *ecl);
        // 确定性 LCG（同 MoonBit 侧 t4 属性测试用法），保证可复现、非手抄。
        let mut state: u32 = 0x1234_5678;
        let mut d = Vec::with_capacity(n);
        for _ in 0..n {
            state = state.wrapping_mul(1_103_515_245).wrapping_add(12_345);
            d.push(((state >> 16) & 0xFF) as u8);
        }
        let o = polynomials::structure(&d, *ecl, *ver);
        let m = ver.max_bytes();
        println!(
            "GOLDEN|STRUCT|{}|{}|{}|{}|{}",
            label,
            *ecl as u8,
            *ver as u8,
            hex(&d),
            hex(&o[..m])
        );
    }
}
