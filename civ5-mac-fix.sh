#!/bin/bash
#
# Patches Civilization V (Steam, macOS) in two independent ways:
#
#   1. Crash fixes. Two crashes that only happen on the 64-bit Mac build:
#      when a civilization regains its original capital, and when the AI
#      re-evaluates a city-state it has no previous stance towards.
#   2. Crossplay switch. Lets this Mac join multiplayer games with Windows
#      players, by announcing the same build number Windows does.
#
# Nothing is downloaded, nothing needs admin rights, and the original game
# library is backed up before it is touched.
#
# Full explanation: https://arthurthiele.com/writing/civ-v-capital-crash/
#
# Usage:
#   ./civ5-mac-fix.sh                  apply the crash fixes
#   ./civ5-mac-fix.sh --crossplay on   play with Windows (not with unswitched Macs)
#   ./civ5-mac-fix.sh --crossplay off  play with other Macs again
#   ./civ5-mac-fix.sh --check          report status, change nothing
#   ./civ5-mac-fix.sh --undo           put everything back as Steam shipped it
#   ./civ5-mac-fix.sh --verbose        show the raw bytes as it works
#   ./civ5-mac-fix.sh --path APP       use a specific "Civilization V.app"

set -euo pipefail

# CvTeam::isHasMet. Stock: push rbp / mov rbp,rsp / mov eax,esi
# / mov al,[rdi+rax+1848] / pop rbp / ret, plus one byte of padding.
# Fixed: xor eax,eax / test esi,esi / js done / mov eax,esi
# / mov al,[rdi+rax+1848] / done: ret.
readonly CAPITAL_STOCK_BYTES="554889e589f08a8407380700005dc390"
readonly CAPITAL_FIXED_BYTES="31c085f6780989f08a840738070000c3"

# CvDiplomacyAI::GetBestApproachTowardsMinorCiv. Stock: movsx esi,[rax+rcx]
# / mov eax,esi / inc al / mov ebx,-1 / cmp al,5 / jbe add_bias.
# Fixed: ... / mov eax,esi / or ebx,-1 / inc al / jz after_add_bias / cmp al,5
# / jbe add_bias. A previous stance of -1 ("none") now skips the bias, which
# is what Windows effectively does: there the stray write lands on the weight
# vector's unused capacity field.
readonly CITY_STATE_STOCK_BYTES="0fbe340889f0fec0bbffffffff3c057639"
readonly CITY_STATE_FIXED_BYTES="0fbe340889f083cbfffec074503c057639"

# Windows takes its multiplayer version from the text in brackets in its file
# version, "1, 0, 3, 279, (403694)". Aspyr's Mac build fills the same slot
# from this line, using its own build number.
readonly VERSION_LINE_MAC='"App.WinFileVersionStr" : "{App.WinFileVersion} ({App.Build})"'
readonly VERSION_LINE_WINDOWS='"App.WinFileVersionStr" : "{App.WinFileVersion} (403694)"'

readonly APP_RELATIVE_PATH="steamapps/common/Sid Meier's Civilization V/Civilization V.app"
readonly DYLIB_RELATIVE_PATH="Contents/MacOS/libCvGameCoreDLL_Expansion2_DLL.dylib"
readonly VERSION_FILE_RELATIVE_PATH="Contents/AspyrAssets/global/String/App.json"
readonly BACKUP_SUFFIX=".backup-before-capital-fix"

mode="apply"
crossplay_target=""
verbose="no"
app_override=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)     mode="check" ;;
    --undo)      mode="undo" ;;
    --crossplay) shift; mode="crossplay"; crossplay_target="${1:-}" ;;
    --verbose)   verbose="yes" ;;
    --path)      shift; app_override="${1:-}" ;;
    --help|-h)   sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done

say() { printf '%s\n' "$1"; }
detail() { [ "$verbose" = "yes" ] && printf '   %s\n' "$1" || true; }
fail() { printf '\n%s\n' "$1" >&2; exit 1; }

if [ "$mode" = "crossplay" ] && [ "$crossplay_target" != "on" ] && [ "$crossplay_target" != "off" ]; then
  fail "Use --crossplay on or --crossplay off."
fi

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

find_app() {
  if [ -n "$app_override" ]; then
    [ -d "$app_override" ] || fail "No app at: $app_override"
    printf '%s\n' "${app_override%/}"
    return 0
  fi
  local root
  while IFS= read -r root; do
    [ -n "$root" ] || continue
    if [ -d "$root/$APP_RELATIVE_PATH" ]; then
      printf '%s\n' "$root/$APP_RELATIVE_PATH"
      return 0
    fi
  done < <(list_steam_roots)
  fail "Could not find Civilization V.

If Steam is installed somewhere unusual, point this script at the app directly:
  bash \"$0\" --path \"/path/to/Civilization V.app\""
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

count_lines_containing() { grep -c -F -- "$2" "$1" || true; }

replace_line_text() {
  /usr/bin/perl -e '
    my ($path, $from, $to) = @ARGV;
    open(my $in, "<:raw", $path) or die "cannot read: $!\n";
    local $/; my $text = <$in>; close($in);
    my $at = index($text, $from);
    die "text not found\n" if $at < 0;
    substr($text, $at, length($from)) = $to;
    open(my $out, ">:raw", $path) or die "cannot write: $!\n";
    print $out $text; close($out);
  ' "$1" "$2" "$3"
}

refuse_if_game_running() {
  pgrep -f "Civilization V.app/Contents/MacOS" >/dev/null 2>&1 &&
    fail "Civilization V is running. Please quit the game, then run this again."
  return 0
}

# Prints "stock OFFSET", "fixed OFFSET", "unknown" or "ambiguous".
patch_state() {
  local stock_offsets fixed_offsets
  stock_offsets="$(find_pattern_offsets "$dylib" "$1")"
  fixed_offsets="$(find_pattern_offsets "$dylib" "$2")"
  local stock_count fixed_count
  stock_count="$(count_of "$stock_offsets")"
  fixed_count="$(count_of "$fixed_offsets")"
  if [ "$stock_count" -eq 1 ] && [ "$fixed_count" -eq 0 ]; then echo "stock $stock_offsets"; return 0; fi
  if [ "$stock_count" -eq 0 ] && [ "$fixed_count" -eq 1 ]; then echo "fixed $fixed_offsets"; return 0; fi
  if [ "$stock_count" -eq 0 ] && [ "$fixed_count" -eq 0 ]; then echo "unknown"; return 0; fi
  echo "ambiguous"
}

version_state() {
  local mac_count windows_count
  mac_count="$(count_lines_containing "$version_file" "$VERSION_LINE_MAC")"
  windows_count="$(count_lines_containing "$version_file" "$VERSION_LINE_WINDOWS")"
  if [ "$mac_count" -eq 1 ] && [ "$windows_count" -eq 0 ]; then echo "mac"; return 0; fi
  if [ "$mac_count" -eq 0 ] && [ "$windows_count" -eq 1 ]; then echo "windows"; return 0; fi
  echo "unknown"
}

resign_or_explain() {
  if codesign --force --sign - "$dylib" >/dev/null 2>&1 && codesign -v "$dylib" >/dev/null 2>&1; then
    return 0
  fi
  fail "The fixes are written but the file could not be re-signed, so macOS may
refuse to load it. Run this script with --undo, or use Steam's Verify integrity
of game files, to put it back."
}

app="$(find_app)"
dylib="$app/$DYLIB_RELATIVE_PATH"
version_file="$app/$VERSION_FILE_RELATIVE_PATH"
backup="$dylib$BACKUP_SUFFIX"

[ -f "$dylib" ] || fail "Found the app, but not its rules library. I have changed nothing."
[ -f "$version_file" ] || fail "Found the app, but not its version file. I have changed nothing."

capital="$(patch_state "$CAPITAL_STOCK_BYTES" "$CAPITAL_FIXED_BYTES")"
city_state="$(patch_state "$CITY_STATE_STOCK_BYTES" "$CITY_STATE_FIXED_BYTES")"
version="$(version_state)"

say ""
detail "$app"
detail "capital fix: $capital   city-state fix: $city_state   version line: $version"

describe_patch() {
  case "$1" in
    stock*) echo "not fixed" ;;
    fixed*) echo "fixed" ;;
    *)      echo "not recognised" ;;
  esac
}

if [ "$mode" = "check" ]; then
  say "Found Civilization V."
  say "  Capital recapture crash:   $(describe_patch "$capital")"
  say "  City-state stance crash:   $(describe_patch "$city_state")"
  case "$version" in
    mac)     say "  Multiplayer:               plays with other Macs (as shipped)" ;;
    windows) say "  Multiplayer:               plays with Windows (crossplay on)" ;;
    *)       say "  Multiplayer:               version file not recognised" ;;
  esac
  exit 0
fi

remove_patch() {
  local state="$1" stock_bytes="$2"
  [ "${state%% *}" = "fixed" ] || return 0
  write_bytes_at "$dylib" "${state#* }" "$stock_bytes"
  removed_any="yes"
}

if [ "$mode" = "undo" ]; then
  refuse_if_game_running
  if [ -f "$backup" ]; then
    cp "$backup" "$dylib"
    rm -f "$backup"
    capital="$(patch_state "$CAPITAL_STOCK_BYTES" "$CAPITAL_FIXED_BYTES")"
    city_state="$(patch_state "$CITY_STATE_STOCK_BYTES" "$CITY_STATE_FIXED_BYTES")"
  fi
  # A backup made by an older version of this script, or after a partial
  # install, can itself contain a fix. Taking the fixes out byte by byte
  # covers that, and the case where there is no backup at all.
  removed_any="no"
  remove_patch "$capital" "$CAPITAL_STOCK_BYTES"
  remove_patch "$city_state" "$CITY_STATE_STOCK_BYTES"
  if [ "$removed_any" = "yes" ]; then
    codesign --force --sign - "$dylib" >/dev/null 2>&1 || fail "Could not re-sign the file.
Steam can restore it: right-click Civilization V, Properties, Installed Files,
Verify integrity of game files."
    say "Crash fixes removed. The file carries a local signature, not Aspyr's;"
    say "Steam's Verify integrity of game files restores the shipped one."
  else
    say "Rules library is as Steam shipped it."
  fi
  if [ "$version" = "windows" ]; then
    replace_line_text "$version_file" "$VERSION_LINE_WINDOWS" "$VERSION_LINE_MAC"
    say "Crossplay switched off."
  fi
  say "Done."
  exit 0
fi

if [ "$mode" = "crossplay" ]; then
  [ "$version" = "unknown" ] && fail "This game's version file is not one I recognise, so I have
changed nothing. Please report it, and mention your game version."
  refuse_if_game_running
  if [ "$crossplay_target" = "on" ]; then
    [ "$version" = "mac" ] && replace_line_text "$version_file" "$VERSION_LINE_MAC" "$VERSION_LINE_WINDOWS"
    [ "$(version_state)" = "windows" ] || fail "The change did not verify. Please report this."
    say "Crossplay is on. This Mac can now join games with Windows players,"
    say "and with other Macs that have crossplay on. It can no longer join"
    say "Macs that have it off. Switch back with:  bash \"$0\" --crossplay off"
  else
    [ "$version" = "windows" ] && replace_line_text "$version_file" "$VERSION_LINE_WINDOWS" "$VERSION_LINE_MAC"
    [ "$(version_state)" = "mac" ] || fail "The change did not verify. Please report this."
    say "Crossplay is off. This Mac plays with other Macs, as shipped."
  fi
  case "$capital$city_state" in
    *stock*) say ""; say "The crash fixes are not applied yet. Run this script with no options to add them." ;;
  esac
  say ""
  exit 0
fi

case "$capital" in unknown|ambiguous) unrecognised="yes" ;; *) unrecognised="no" ;; esac
case "$city_state" in unknown|ambiguous) unrecognised="yes" ;; esac
if [ "$unrecognised" = "yes" ]; then
  fail "This does not look like a version of the game I recognise, so I have
changed nothing. That is the safe outcome. Please report it rather than
forcing it, and mention your game version."
fi

if [ "${capital%% *}" = "fixed" ] && [ "${city_state%% *}" = "fixed" ]; then
  say "Found Civilization V. Both crash fixes are already applied. Nothing to do."
  exit 0
fi

refuse_if_game_running

# Only a fully stock library is worth keeping as "the original". Refreshing
# the backup here also stops an old one surviving a game update.
if [ "${capital%% *}" = "stock" ] && [ "${city_state%% *}" = "stock" ]; then
  cp "$dylib" "$backup"
  say "Found Civilization V. Original backed up alongside it."
else
  say "Found Civilization V, with one fix already in place."
fi

apply_patch() {
  local state="$1" stock_bytes="$2" fixed_bytes="$3" label="$4"
  [ "${state%% *}" = "stock" ] || return 0
  local offset="${state#* }"
  detail "$label: patching at byte offset $offset with $fixed_bytes"
  write_bytes_at "$dylib" "$offset" "$fixed_bytes"
  if [ "$(find_pattern_offsets "$dylib" "$fixed_bytes")" != "$offset" ]; then
    write_bytes_at "$dylib" "$offset" "$stock_bytes"
    fail "The change did not verify, so I have put those bytes back."
  fi
  say "Fixed: $label."
}

apply_patch "$capital" "$CAPITAL_STOCK_BYTES" "$CAPITAL_FIXED_BYTES" "capital recapture crash"
apply_patch "$city_state" "$CITY_STATE_STOCK_BYTES" "$CITY_STATE_FIXED_BYTES" "city-state stance crash"

# Patching invalidates Aspyr's signature; macOS needs a valid one to load the file.
resign_or_explain
say "File re-signed so macOS will load it."

say ""
say "All done. To play with Windows friends as well, run:"
say "  bash \"$0\" --crossplay on"
say "To undo everything at any time, run:  bash \"$0\" --undo"
say ""
