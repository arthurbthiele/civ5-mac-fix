#!/bin/bash
#
# Fixes the Civilization V crash on macOS that happens whenever a civilization
# regains its original capital — by recapture, liberation, or a peace deal.
#
# It changes 16 bytes in one function of the game's rules library, adding the
# bounds check that Firaxis left out, then re-signs the file so macOS will load
# it. Nothing is downloaded, nothing needs admin rights, and the original file is
# backed up first.
#
# Full explanation: https://arthurthiele.com/writing/civ-v-capital-crash/
#
# Usage:
#   ./fix-civ5-capital-crash.sh              apply the fix
#   ./fix-civ5-capital-crash.sh --check      report status, change nothing
#   ./fix-civ5-capital-crash.sh --undo       restore the backup
#   ./fix-civ5-capital-crash.sh --verbose    show the raw bytes as it works
#   ./fix-civ5-capital-crash.sh --path FILE  use a specific dylib

set -euo pipefail

# The stock function: push rbp / mov rbp,rsp / mov eax,esi / mov al,[rdi+rax+1848]
# / pop rbp / ret, plus one byte of padding.
readonly STOCK_BYTES="554889e589f08a8407380700005dc390"

# The fixed function: xor eax,eax / test esi,esi / js done / mov eax,esi
# / mov al,[rdi+rax+1848] / done: ret.  Same 16 bytes, no file resizing.
readonly FIXED_BYTES="31c085f6780989f08a840738070000c3"

readonly DYLIB_RELATIVE_PATH="steamapps/common/Sid Meier's Civilization V/Civilization V.app/Contents/MacOS/libCvGameCoreDLL_Expansion2_DLL.dylib"
readonly BACKUP_SUFFIX=".backup-before-capital-fix"

mode="apply"
verbose="no"
dylib_override=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)   mode="check" ;;
    --undo)    mode="undo" ;;
    --verbose) verbose="yes" ;;
    --path)    shift; dylib_override="${1:-}" ;;
    --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done

say() { printf '%s\n' "$1"; }
detail() { [ "$verbose" = "yes" ] && printf '   %s\n' "$1" || true; }
fail() { printf '\n%s\n' "$1" >&2; exit 1; }

# Every Steam library on this Mac: the default one, plus any extra drives the
# user has added (Steam records those in libraryfolders.vdf).
list_steam_roots() {
  local default_root="$HOME/Library/Application Support/Steam"
  printf '%s\n' "$default_root"
  local library_index="$default_root/steamapps/libraryfolders.vdf"
  [ -f "$library_index" ] || return 0
  grep -o '"path"[[:space:]]*"[^"]*"' "$library_index" 2>/dev/null \
    | sed 's/.*"path"[[:space:]]*"//; s/"$//'
}

find_dylib() {
  if [ -n "$dylib_override" ]; then
    [ -f "$dylib_override" ] || fail "No file at: $dylib_override"
    printf '%s\n' "$dylib_override"
    return 0
  fi
  local root
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    if [ -f "$root/$DYLIB_RELATIVE_PATH" ]; then
      printf '%s\n' "$root/$DYLIB_RELATIVE_PATH"
      return 0
    fi
  done < <(list_steam_roots)
  fail "Could not find Civilization V.

If Steam is installed somewhere unusual, point this script at the file directly:
  bash \"$0\" --path \"/path/to/libCvGameCoreDLL_Expansion2_DLL.dylib\""
}

# Byte offsets of every occurrence of a hex pattern, comma separated.
find_pattern_offsets() {
  /usr/bin/perl -e '
    open(my $fh, "<:raw", $ARGV[0]) or die "cannot read: $!\n";
    local $/; my $data = <$fh>; close($fh);
    my $needle = pack("H*", $ARGV[1]);
    my (@hits, $pos); $pos = 0;
    while (($pos = index($data, $needle, $pos)) >= 0) { push @hits, $pos; $pos++; }
    print join(",", @hits);
  ' "$1" "$2"
}

count_of() { local list="$1"; [ -z "$list" ] && echo 0 || awk -F, '{print NF}' <<< "$list"; }

write_bytes_at() {
  /usr/bin/perl -e '
    open(my $fh, "+<:raw", $ARGV[0]) or die "cannot write: $!\n";
    seek($fh, $ARGV[1], 0) or die "seek failed\n";
    print $fh pack("H*", $ARGV[2]);
    close($fh);
  ' "$1" "$2" "$3"
}

refuse_if_game_running() {
  pgrep -f "Civilization V" >/dev/null 2>&1 &&
    fail "Civilization V is running. Please quit the game, then run this again."
  return 0
}

dylib="$(find_dylib)"
backup="$dylib$BACKUP_SUFFIX"

stock_offsets="$(find_pattern_offsets "$dylib" "$STOCK_BYTES")"
fixed_offsets="$(find_pattern_offsets "$dylib" "$FIXED_BYTES")"
stock_count="$(count_of "$stock_offsets")"
fixed_count="$(count_of "$fixed_offsets")"

say ""
detail "$dylib"
detail "stock pattern matches: $stock_count   fixed pattern matches: $fixed_count"

if [ "$mode" = "undo" ]; then
  [ -f "$backup" ] || fail "No backup found next to the game, so there is nothing to undo.
You can also restore the original through Steam: right-click Civilization V,
Properties, Installed Files, Verify integrity of game files."
  refuse_if_game_running
  cp "$backup" "$dylib"
  rm -f "$backup"
  say "Found Civilization V. Original restored — back to how Steam shipped it."
  exit 0
fi

if [ "$fixed_count" -eq 1 ] && [ "$stock_count" -eq 0 ]; then
  say "Found Civilization V — this copy is already fixed. Nothing to do."
  exit 0
fi

if [ "$stock_count" -eq 0 ]; then
  fail "This does not look like a version of the game I recognise, so I have
changed nothing. That is the safe outcome — please report it rather than
forcing it, and mention your game version."
fi

if [ "$stock_count" -ne 1 ]; then
  fail "Found $stock_count possible places to patch and expected exactly one,
so I have changed nothing. Please report this."
fi

offset="$stock_offsets"

if [ "$mode" = "check" ]; then
  say "Found Civilization V — this copy is affected by the crash and can be fixed."
  say "Run the script again without --check to fix it."
  exit 0
fi

refuse_if_game_running

detail "patching at byte offset $offset"
detail "before: $STOCK_BYTES"
detail "after:  $FIXED_BYTES"

[ -f "$backup" ] || cp "$dylib" "$backup"
say "Found Civilization V. Original backed up alongside it."

write_bytes_at "$dylib" "$offset" "$FIXED_BYTES"

verify="$(find_pattern_offsets "$dylib" "$FIXED_BYTES")"
[ "$verify" = "$offset" ] || {
  cp "$backup" "$dylib"
  fail "The change did not verify, so the original has been put back. Nothing was altered."
}
say "Fix applied."

# Patching invalidates Aspyr's signature; macOS needs a valid one to load the file.
if ! codesign --force --sign - "$dylib" >/dev/null 2>&1; then
  cp "$backup" "$dylib"
  fail "Could not re-sign the file, so the original has been put back."
fi
if ! codesign -v "$dylib" >/dev/null 2>&1; then
  cp "$backup" "$dylib"
  fail "The re-signed file did not verify, so the original has been put back."
fi
say "File re-signed so macOS will load it."

say ""
say "All done. Start Civilization V and load the save that was crashing."
say "To undo this at any time, run:  bash \"$0\" --undo"
say ""
