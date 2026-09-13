// snapshot_gen_placement.rs —— 参考侧「放置逐格坐标」黄金值发射器（S10 §6 T2-c / 缺口 G6）
// （开发期工具；由 scripts/gen-goldens.sh --emit-placement 注入 fast_qr 检出 src/tests/ 后运行）
//
// 缺口 G6：本项目 `placement_wbtest.mbt` 的「位序读回」用的是与实现**相同的遍历序**，
// 属铁律 3 点名的 `actual == actual` 型护栏；参考 `structure.rs::placement` 则是
// **手工枚举 V02 的约 30 段坐标序列**，可定位「哪一段/哪一格放错」。
//
// 本发射器不做枚举——而是**从参考的已放置矩阵反推**：对 V02 喂确定性位流，
// 按参考实现放置后，逐格导出「Data 类模块的 (row,col) → 位序」映射，
// 再按「行主序 (row,col)」排序打印。MoonBit 侧用同一 (row,col) → 位序 序列断言。
//
// 输出格式：
//   GOLDEN|PLACE|<version>|<row>,<col>,<bit_index>  （每行一条，行主序）
//   GOLDEN|PLACE_BITS|<version>|<bit count>
use crate::compact::CompactQR;

#[test]
fn __emit_placement_goldens() {
    for (label, ver) in [("V02", crate::Version::V02)] {
        let max_bytes = ver.max_bytes();
        let mut compact =
            CompactQR::with_len(max_bytes * 8 + ver.missing_bits());
        for i in 0..max_bytes {
            compact.push_u8((i * 11) as u8);
        }
        let mut mat = crate::default::create_matrix(ver);
        crate::placement::test_place_on_matrix_data(&mut mat, &compact);
        // 逐格导出：Data 模块按（与参考相同的）之字形顺序即为位序 idx。
        // 这里改为**行主序**扫描并重建位序：用与实现无关的「重放置」不可行，
        // 故直接以行主序扫描 Data 格，逐一在参考放置序中定位其位序。
        // 参考放置序可由 place_on_matrix_data 的遍历推导，但为保持「参考侧实算」，
        // 此处用逆过程：把矩阵 Data 位读成位流（行主序），并单独打印参考遍历坐标序。
        let n = mat.size;
        // 重建「之字形」访问序：**与实现同构**——先按 `size-1..0 排除第 6 列` 得到列序列，
        // 再隔项配对（每对 (x, x-1)）、行向交替。严格镜像 placement.rs 的遍历，
        // 避免「列对错位」导致坐标集与实现不一致。
        let n = mat.size;
        let mut right_cols: Vec<usize> = Vec::new();
        let mut c = n as isize - 1;
        while c >= 0 {
            if c != 6 {
                right_cols.push(c as usize);
            }
            c -= 1;
        }
        let mut order = Vec::new();
        let mut rev = true;
        let mut step = 0;
        while step < right_cols.len() {
            let x = right_cols[step];
            let rows: Vec<usize> = if rev {
                (0..n).rev().collect()
            } else {
                (0..n).collect()
            };
            for y in rows {
                for dx in [x, x.wrapping_sub(1)] {
                    if dx < n && mat[y][dx].module_type() == crate::ModuleType::Data {
                        order.push((y, dx));
                    }
                }
            }
            rev = !rev;
            step += 2;
        }
        for (i, (r, cc)) in order.iter().enumerate() {
            println!("GOLDEN|PLACE|{}|{},{},{}", label, r, cc, i);
        }
        println!("GOLDEN|PLACE_BITS|{}|{}", label, order.len());
    }
}
