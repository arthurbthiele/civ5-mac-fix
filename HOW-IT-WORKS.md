# How the Civilization V Mac fix works

The details behind [`civ5-mac-fix.sh`](civ5-mac-fix.sh): exactly what it changes, how to make the
same changes by hand, and how to check it for yourself. For how to use it, see the
[README](README.md).

## The capital crash

One function, `CvTeam::isHasMet`, which reads a yes/no flag out of an array. The game sometimes
calls it with an index of `-1`, meaning "no team". On 32-bit Windows that misreads a harmless nearby
byte. On the 64-bit Mac build the same arithmetic points four gigabytes away, and the game dies.

The fix adds the missing check in the sixteen bytes the function already occupies:

```
before:  55 48 89 e5 89 f0 8a 84 07 38 07 00 00 5d c3 90
after:   31 c0 85 f6 78 09 89 f0 8a 84 07 38 07 00 00 c3
```

```
      31 c0                    xor  eax, eax            ; default: false
      85 f6                    test esi, esi
      78 09                    js   done                ; negative index -> return false
      89 f0                    mov  eax, esi
      8a 84 07 38 07 00 00     mov  al, [rdi+rax+1848]
done: c3                       ret
```

## The city-state crash

Each turn, an AI re-decides its stance towards every city-state, and gives a small bonus to whatever
stance it held before. For a city-state that has just been liberated back into the game there is no
previous stance, which the game records as `-1`, and the bonus gets written to slot `-1` of a short
list. On Windows that lands on a spare field next to the list and nothing comes of it. On the Mac it
is the same four-gigabyte miss.

The fix skips the bonus when there is no previous stance, which is also what Windows ends up doing in
effect. Seven bytes change, inside `CvDiplomacyAI::GetBestApproachTowardsMinorCiv`:

```
before:  0f be 34 08 89 f0 fe c0 bb ff ff ff ff 3c 05 76 39
after:   0f be 34 08 89 f0 83 cb ff fe c0 74 50 3c 05 76 39
```

```
      0f be 34 08     movsx esi, byte [rax+rcx]   ; previous stance
      89 f0           mov   eax, esi
      83 cb ff        or    ebx, -1               ; default return value, as before
      fe c0           inc   al
      74 50           jz    after_bonus           ; previous stance was -1: skip the bonus
      3c 05           cmp   al, 5
      76 39           jbe   add_bonus
```

Both changes are in `libCvGameCoreDLL_Expansion2_DLL.dylib`, the rules library the game uses when
Brave New World is installed. Patching it invalidates Aspyr's code signature on that one file, so the
script re-signs it locally. Without that, macOS won't load it.

## Multiplayer with Windows

Civilization V only lets players connect when they announce the same build number. Windows announces
`403694`. The Mac build runs the same rules, but announces Aspyr's own number, `180925`, which it
takes from one line in a text file inside the app:

```
Contents/AspyrAssets/global/String/App.json

before:  "App.WinFileVersionStr" : "{App.WinFileVersion} ({App.Build})",
after:   "App.WinFileVersionStr" : "{App.WinFileVersion} (403694)",
```

That one line is the whole change, and `--play-with macs` puts it back. No program code changes
for multiplayer.

## Doing it by hand

If you would rather not run someone else's script, which is reasonable, everything above is enough
to do it yourself:

1. Back up `Civilization V.app/Contents/MacOS/libCvGameCoreDLL_Expansion2_DLL.dylib`, then open it
   in a hex editor.
2. Search for each "before" byte sequence. Each has exactly one match. If you find none, or more than
   one, stop: you have a build this has not been tested on.
3. Replace each with its "after" sequence, save, and run
   `codesign --force --sign - "<path to that file>"` in Terminal.
4. To play with Windows, edit the line in `App.json` shown above with any text editor.

## Checking it for yourself

- The script is about 320 lines and written to be read. Read it before you run it.
- It downloads nothing, needs no admin rights, and asks for no passwords.
- It finds each place to patch by its exact bytes and **refuses to write anything unless it finds
  exactly one match**, so it can't mangle a version it doesn't recognise.
- It backs up the original library first, and `--undo` puts things back.
- It never touches the game's main program, only the rules library and one text file.
- Everything here is independently checkable: Firaxis released the rules-engine source publicly, and
  `objdump` will show you the same functions on your own machine.

**Don't install a patched game file from a stranger**, including from me. That is why this is a
script that edits your own copy, and not a replacement file.
