#!/usr/bin/env bash
# gen-goldens.sh —— 黄金值一键重建 / 校验（S10 §6 T0-a / T6-b）
#
# 统一入口：所有「与参考逐位一致」的黄金值都必须能由本脚本在**钉版参考**上重建，
# 并可用 --verify 校验仓库内常量未漂移（铁律 1：参考值禁止手抄）。
#
# 钉版参考：fast_qr commit 53e8c99（Cargo.toml version 0.14.0）。
#
# 子命令:
#   bash scripts/gen-goldens.sh --verify         # 只校验（默认；零差异退出 0）
#   bash scripts/gen-goldens.sh --regen-tables   # 生成常量表全表指纹（T1-f）
#   bash scripts/gen-goldens.sh --emit-rs        # 发射 division/structure 黄金向量（T1-c/T1-d）
#   bash scripts/gen-goldens.sh --emit-default   # 抽取独立数字真值矩阵（T0-c）
#   bash scripts/gen-goldens.sh --verify-default # 校验独立数字真值未漂移（T0-c）
#   bash scripts/gen-goldens.sh --emit-score     # 发射逐行/逐列打分明细（T2-a/T2-b）
#   bash scripts/gen-goldens.sh --emit-placement # 发射放置逐格坐标序列（T2-c）
#   bash scripts/gen-goldens.sh --emit-all-rs    # 一次发射全部「参考侧实算」向量（T1-c/d + T2-a/b + T2-c）
#
# 环境变量:
#   FAST_QR_DIR   参考检出目录（默认 $HOME/.cache/fast_qr_wasm/fast_qr，回退 $HOME/.cache/fast_qr）
#   EXPECT_COMMIT 期望参考 commit（默认 53e8c99）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPECT_COMMIT="${EXPECT_COMMIT:-53e8c99}"

# 1) 定位参考检出（优先已缓存目录）
REF="${FAST_QR_DIR:-}"
if [[ -z "$REF" ]]; then
  for cand in "$HOME/.cache/fast_qr_wasm/fast_qr" "$HOME/.cache/fast_qr" "$ROOT/../fast_qr"; do
    if [[ -d "$cand/src" ]]; then REF="$cand"; break; fi
  done
fi
if [[ -z "$REF" || ! -d "$REF/src" ]]; then
  echo ">> 未找到 fast_qr 参考检出。请先 clone（钉版 $EXPECT_COMMIT）或设 FAST_QR_DIR。" >&2
  echo "   git clone https://github.com/erwanvivien/fast_qr.git && git -C fast_qr checkout $EXPECT_COMMIT" >&2
  exit 2
fi

# 2) 校验参考 commit（钉版铁律）
if [[ -d "$REF/.git" ]]; then
  CUR="$(git -C "$REF" rev-parse --short HEAD 2>/dev/null || true)"
  if [[ -n "$CUR" && "$CUR" != "$EXPECT_COMMIT"* && "$EXPECT_COMMIT" != "$CUR"* ]]; then
    echo "!! 参考 commit 不符：期望 $EXPECT_COMMIT，实际 $CUR" >&2
    echo "   钉版铁律要求黄金值只在 $EXPECT_COMMIT 上重建。" >&2
    exit 3
  fi
  echo ">> 参考检出: $REF @ $CUR（钉版 $EXPECT_COMMIT）"
else
  echo ">> 参考检出: $REF（无 .git，跳过 commit 校验）"
fi

# 参考侧实算器（注入 fast_qr 检出 src/tests/ 后跑 cargo test）：
#   $1 = 脚本文件（scripts/ 下）  $2 = Rust test 函数名
run_ref_emitter() {
  local src="$1" fn="$2"
  local dst="$REF/src/tests/$(basename "$src")"
  local modname="${src##*/}"; modname="${modname%.rs}"
  cp "$src" "$dst"
  local MODFILE="$REF/src/tests/mod.rs"
  local BACKUP; BACKUP="$(mktemp)"; cp "$MODFILE" "$BACKUP"
  if ! grep -q "$modname" "$MODFILE"; then printf 'mod %s;\n' "$modname" >> "$MODFILE"; fi
  ( cd "$REF" && cargo test --lib "$fn" -- --nocapture 2>/dev/null | grep "^GOLDEN|" ) || true
  cp "$BACKUP" "$MODFILE"; rm -f "$BACKUP" "$dst"
}

MODE="${1:---verify}"
case "$MODE" in
  --verify)
    echo "=== 校验常量表全表指纹（T1-f） ==="
    python3 "$SCRIPT_DIR/snapshot_gen_tables.py" --ref "$REF" --verify
    echo "=== 校验独立数字真值（T0-c） ==="
    python3 "$SCRIPT_DIR/snapshot_gen_default.py" --ref "$REF" --verify
    echo "=== 校验打分明细（T2-a/T2-b） ==="
    python3 "$SCRIPT_DIR/snapshot_verify_score.py" --ref "$REF" --verify
    echo "=== 校验放置逐格坐标（T2-c） ==="
    python3 "$SCRIPT_DIR/snapshot_verify_placement.py" --ref "$REF" --verify
    ;;
  --emit-default)
    echo "=== 抽取独立数字真值矩阵（T0-c） ==="
    python3 "$SCRIPT_DIR/snapshot_gen_default.py" --ref "$REF"
    ;;
  --verify-default)
    echo "=== 校验独立数字真值（T0-c） ==="
    python3 "$SCRIPT_DIR/snapshot_gen_default.py" --ref "$REF" --verify
    ;;
  --regen-tables)
    echo "=== 重建常量表全表指纹（T1-f） ==="
    python3 "$SCRIPT_DIR/snapshot_gen_tables.py" --ref "$REF"
    ;;
  --emit-rs)
    echo "=== 发射 division/structure 黄金向量（T1-c/T1-d） ==="
    run_ref_emitter "$SCRIPT_DIR/snapshot_gen_rs_vectors.rs" __emit_goldens
    ;;
  --emit-score)
    echo "=== 发射打分明细（T2-a/T2-b） ==="
    run_ref_emitter "$SCRIPT_DIR/snapshot_gen_score.rs" __emit_score_goldens
    ;;
  --emit-placement)
    echo "=== 发射放置逐格坐标（T2-c） ==="
    run_ref_emitter "$SCRIPT_DIR/snapshot_gen_placement.rs" __emit_placement_goldens
    ;;
  --emit-all-rs)
    echo "=== 一次发射全部参考侧实算向量 ==="
    run_ref_emitter "$SCRIPT_DIR/snapshot_gen_rs_vectors.rs" __emit_goldens
    run_ref_emitter "$SCRIPT_DIR/snapshot_gen_score.rs" __emit_score_goldens
    run_ref_emitter "$SCRIPT_DIR/snapshot_gen_placement.rs" __emit_placement_goldens
    ;;
  *)
    echo "用法: bash scripts/gen-goldens.sh [--verify|--regen-tables|--emit-rs|--emit-score|--emit-placement|--emit-all-rs]" >&2
    exit 2
    ;;
esac
