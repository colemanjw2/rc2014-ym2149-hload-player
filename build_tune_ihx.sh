#!/usr/bin/env bash
set -euo pipefail

# Build an RC2014 YM2149 tune into Intel HEX (.ihx) for HLOAD.
# This version NEVER edits PTxPlay.asm. It writes/overwrites tune.inc instead.
#
# Requirements: sjasmplus, z88dk-appmake
#
# One-time setup (already done on your side):
#   In PTxPlay.asm replace the incbin line with:
#       include "tune.inc"
#   And keep a tune.inc file in this folder.
#
# Usage:
#   ./build_tune_ihx.sh altitude.pt3
#   ./build_tune_ihx.sh tunes/altitude.pt3
#
# Outputs:
#   build/<tune_basename>.bin
#   build/<tune_basename>.ihx
#
# Optional env vars:
#   ORG=49152      # load address (default 49152 = 0xC000)
#   OUTDIR=/path   # copy final ihx there (optional)

cd "$(cd "$(dirname "$0")" && pwd)"

ORG="${ORG:-49152}"   # 0xC000 default
ASM="PTxPlay.asm"
INC="tune.inc"

die() { echo "ERROR: $*" >&2; exit 1; }

command -v sjasmplus >/dev/null 2>&1 || die "sjasmplus not found in PATH"
command -v z88dk-appmake >/dev/null 2>&1 || die "z88dk-appmake not found in PATH"
[[ -f "$ASM" ]] || die "missing $ASM in $(pwd)"
[[ -f "$INC" ]] || die "missing $INC in $(pwd) (create tune.inc first)"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <tune.pt2|tune.pt3|path/to/tune>" >&2
  exit 2
fi

TUNE_IN="$1"

# Resolve tune file location
if [[ -f "$TUNE_IN" ]]; then
  TUNE_PATH="$TUNE_IN"
elif [[ -f "tunes/$TUNE_IN" ]]; then
  TUNE_PATH="tunes/$TUNE_IN"
elif [[ -f "tunes/$(basename "$TUNE_IN")" ]]; then
  TUNE_PATH="tunes/$(basename "$TUNE_IN")"
elif [[ -f "$(basename "$TUNE_IN")" ]]; then
  TUNE_PATH="$(basename "$TUNE_IN")"
else
  die "tune not found: '$TUNE_IN' (also tried 'tunes/$TUNE_IN')"
fi

case "$TUNE_PATH" in
  *.pt2|*.pt3) ;;
  *) die "tune must be .pt2 or .pt3 (got: $TUNE_PATH)" ;;
esac

# Prefer a relative path that sjasmplus can resolve from this folder
# (so the .asm include doesn't depend on your current working directory)
if [[ -f "$TUNE_PATH" ]]; then
  :
elif [[ -f "$(pwd)/$TUNE_PATH" ]]; then
  TUNE_PATH="$(pwd)/$TUNE_PATH"
fi

TUNE_FILE="$(basename "$TUNE_PATH")"
BASE="${TUNE_FILE%.*}"

mkdir -p build

# Sanity: ensure PTxPlay.asm includes tune.inc (avoid silent wrong build)
grep -qiE '^[[:space:]]*include[[:space:]]+"?tune\.inc"?' "$ASM" \
  || die "$ASM does not appear to include tune.inc (expected: include \"tune.inc\")"

# Write/overwrite tune.inc (this is the only file we modify)
cat > "$INC" <<EOF
    incbin "$TUNE_PATH"
EOF

echo "[YM2149] tune: $TUNE_PATH"
echo "[YM2149] inc:  $INC  (written)"
echo "[YM2149] org:  $ORG (0x$(printf '%X' "$ORG"))"

BIN="build/${BASE}.bin"
IHX="build/${BASE}.ihx"

rm -f "$BIN" "$IHX" "build/${BASE}.bin.ihx"

# Assemble to raw binary
sjasmplus "$ASM" --raw="$BIN" >/dev/null

# Convert binary to Intel HEX for HLOAD
z88dk-appmake +rom -b "$BIN" --org "$ORG" --ihex >/dev/null

# Normalize output name (z88dk sometimes produces .bin.ihx)
if [[ -f "build/${BASE}.ihx" ]]; then
  :
elif [[ -f "build/${BASE}.bin.ihx" ]]; then
  mv -f "build/${BASE}.bin.ihx" "build/${BASE}.ihx"
else
  NEWEST_IHX="$(ls -t build/*.ihx 2>/dev/null | head -n 1 || true)"
  [[ -n "$NEWEST_IHX" ]] || die ".ihx not produced"
  mv -f "$NEWEST_IHX" "build/${BASE}.ihx"
fi

# Optional copy-out
if [[ -n "${OUTDIR:-}" ]]; then
  mkdir -p "$OUTDIR"
  cp -f "build/${BASE}.ihx" "$OUTDIR/"
  echo "[YM2149] copied: $OUTDIR/${BASE}.ihx"
fi

echo "[YM2149] built: $BIN"
echo "[YM2149] built: build/${BASE}.ihx"
