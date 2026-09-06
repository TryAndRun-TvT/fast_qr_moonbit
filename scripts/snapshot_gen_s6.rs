// snapshot_gen_s6.rs —— S6 全量快照参考数据生成器（开发期工具，不参与 push CI）
//
// 用途：在具备 Rust 环境 + fast_qr v0.14.0 参考库处生成 S6 端到端快照的参考全矩阵 hex，
//       供 MoonBit lib/s6_snapshot_test.mbt 逐位对齐（roadmap「表与快照禁止手抄」铁律）。
// 用法：
//   1) 克隆 fast_qr v0.14.0 到本地（scripts/setup-rust.sh 已配 Rust 工具链）。
//   2) 将本文件拷入 fast_qr/examples/snapshot_gen_s6.rs，然后
//        bash scripts/setup-rust.sh
//        cd <fast_qr> && cargo run --release --example snapshot_gen_s6 < cases.txt
//   3) 输入 cases.txt 每行：内容<TAB>mode(0/1/2/NA)<TAB>ecl(0-3/NA)<TAB>version(1-40/NA)<TAB>mask(0-7/NA)
//      mode/ecl/version/mask 为 NA 即走 fast_qr 自动（QRBuilder 全 None）。输出每行：
//        CASE|<idx>|<content>|<mode>|<ecl>|<ver>|<mask>|<全矩阵hex>
//   4) 输出 hex 即为 MoonBit 侧期望，人工转成 lib/s6_snapshot_test.mbt 常量（禁止手抄以外禁止）。
//
use fast_qr::qr::{QRBuilder, QRCodeError};
use fast_qr::{Mode, ECL, Version, Mask};
use std::io::{self, Read, Write};

fn hex_bytes(data: &[u8]) -> String { data.iter().map(|b| format!("{:02x}", b)).collect() }

fn ver_from(n: u8) -> Version {
    // V01..V40 discriminants are 0..39 sequentially
    debug_assert!(n>=1 && n<=40);
    unsafe { std::mem::transmute::<u8, Version>(n-1) }
}

fn gen(content:&str, mode:Option<Mode>, ecl:Option<ECL>, ver:Option<Version>, mask:Option<Mask>) -> Result<(u8,u8,u8,Option<u8>,usize,String), QRCodeError> {
    let mut b = QRBuilder::new(content.to_string());
    if let Some(m)=mode { b.mode(m); }
    if let Some(e)=ecl { b.ecl(e); }
    if let Some(v)=ver { b.version(v); }
    if let Some(m)=mask { b.mask(m); }
    let qr = b.build()?;
    let size=qr.size;
    let mstr:u8 = match qr.mode { Some(Mode::Numeric)=>0,Some(Mode::Alphanumeric)=>1,Some(Mode::Byte)=>2,_=>99 };
    let ecl = qr.ecl.map(|x|(x as u8)).unwrap_or(99);
    let ver = qr.version.map(|x|(x as u8)+1).unwrap_or(0);
    let mask = qr.mask.map(|x|(x as u8));
    let mut data=Vec::with_capacity(size*size);
    for i in 0..size*size { data.push(qr.data[i].0); }
    Ok((mstr,ecl,ver,mask,size,hex_bytes(&data)))
}

fn parse_mode(s:&str)->Option<Mode>{ match s { "0"=>Some(Mode::Numeric),"1"=>Some(Mode::Alphanumeric),"2"=>Some(Mode::Byte),_=>None } }
fn parse_ecl(s:&str)->Option<ECL>{ match s { "0"=>Some(ECL::L),"1"=>Some(ECL::M),"2"=>Some(ECL::Q),"3"=>Some(ECL::H),_=>None } }
fn parse_ver(s:&str)->Option<Version>{ match s.parse::<u8>() { Ok(n) if n>=1&&n<=40=>Some(ver_from(n)), _=>None } }
fn parse_mask(s:&str)->Option<Mask>{ match s { "0"=>Some(Mask::Checkerboard),"1"=>Some(Mask::HorizontalLines),"2"=>Some(Mask::VerticalLines),"3"=>Some(Mask::DiagonalLines),"4"=>Some(Mask::LargeCheckerboard),"5"=>Some(Mask::Fields),"6"=>Some(Mask::Diamonds),"7"=>Some(Mask::Meadow),_=>None } }

fn main(){
    let stdin = io::stdin();
    let mut out = io::BufWriter::new(io::stdout());
    let mut lines = String::new();
    stdin.lock().read_to_string(&mut lines).unwrap();
    let mut results = Vec::new();
    for (idx, raw) in lines.lines().enumerate(){
        if raw.trim().is_empty(){continue}
        let parts:Vec<&str>=raw.split('\t').collect();
        if parts.len()<5 { eprintln!("bad line {}",idx); continue }
        let content=parts[0];
        let mode=parse_mode(parts[1]); let ecl=parse_ecl(parts[2]); let ver=parse_ver(parts[3]); let mask=parse_mask(parts[4]);
        match gen(content,mode,ecl,ver,mask){
            Ok((m,e,v,mk,size,hex))=>{
                let mkstr = match mk { Some(x)=>x.to_string(), None=>"null".into() };
                results.push(format!("CASE|{}|{}|{}|{}|{}|{}|{}", idx, content, m, e, v, mkstr, hex));
            }
            Err(_)=>{ eprintln!("ERR idx={} content={}", idx, content); }
        }
    }
    writeln!(out,"{}",results.join("\n")).unwrap();
    out.flush().unwrap();
}
