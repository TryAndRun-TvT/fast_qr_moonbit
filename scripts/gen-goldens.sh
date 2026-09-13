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

MODE="${1:---verify}"
case "$MODE" in
  --verify)
    echo "=== 校验常量表全表指纹（T1-f） ==="
    python3 "$SCRIPT_DIR/snapshot_gen_tables.py" --ref "$REF" --verify
    echo "=== 校验独立数字真值（T0-c） ==="
    python3 "$SCRIPT_DIR/snapshot_gen_default.py" --ref "$REF" --verify
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
    RS="$REF/src/tests/snapshot_gen_rs_vectors.rs"
    cp "$SCRIPT_DIR/snapshot_gen_rs_vectors.rs" "$RS"
    # 幂等追加 mod（运行后还原）
    MODFILE="$REF/src/tests/mod.rs"
    BACKUP="$(mktemp)"; cp "$MODFILE" "$BACKUP"
    if ! grep -q "snapshot_gen_rs_vectors" "$MODFILE"; then
      printf 'mod snapshot_gen_rs_vectors;\n' >> "$MODFILE"
    fi
    ( cd "$REF" && cargo test --lib __emit_goldens -- --nocapture 2>/dev/null | grep '^GOLDEN|' ) || true
    cp "$BACKUP" "$MODFILE"; rm -f "$BACKUP" "$RS"
    ;;
  *)
    echo "用法: bash scripts/gen-goldens.sh [--verify|--regen-tables|--emit-rs]" >&2
    exit 2
    ;;
esac
