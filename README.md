# Civilization V — capital recapture crash fix (macOS)

Civ V on macOS crashes whenever a civilization **regains its original capital** — by recapture, by
liberation, or through a peace deal. The crash is deterministic: reloading the autosave and replaying
the turn hits it again, which can make a long save unplayable.

This is a 16-byte fix for the bug that causes it. It's a real bug in the game's rules engine, present
since 2013, harmless on Windows and fatal on the 64-bit Mac build.

Full write-up of the cause: **POST_URL**

Affects any Mac running macOS Catalina (2019) or later — Intel or Apple Silicon.

---

## Just fix it

**1.** Download [`fix-civ5-capital-crash.sh`](fix-civ5-capital-crash.sh) — click the link, then the
download button. It'll land in your Downloads folder.

**2.** Quit Civilization V if it's running.

**3.** Open **Terminal** (press `Cmd`+`Space`, type `Terminal`, press Enter), then copy this line,
paste it into the Terminal window, and press Enter:

```
cd ~/Downloads && bash fix-civ5-capital-crash.sh
```

You should see:

```
Found Civilization V. Original backed up alongside it.
Fix applied.
File re-signed so macOS will load it.

All done. Start Civilization V and load the save that was crashing.
```

That's it. Start the game and load your save.

**Not sure if you're affected?** Run this instead — it only looks, and changes nothing:

```
cd ~/Downloads && bash fix-civ5-capital-crash.sh --check
```

**If it can't find your game** (Steam library on an external drive, say), point it at the file:

```
bash fix-civ5-capital-crash.sh --path "/path/to/libCvGameCoreDLL_Expansion2_DLL.dylib"
```

## Undoing it

```
cd ~/Downloads && bash fix-civ5-capital-crash.sh --undo
```

Steam's **Verify integrity of game files** also restores the original, and any game update will
undo the fix as well — just run the script again afterwards.

## What it actually changes

One function, `CvTeam::isHasMet`, which reads a yes/no flag out of an array. The game sometimes calls
it with an index of `-1`, meaning "no team". On 32-bit Windows that misreads a harmless nearby byte;
on the 64-bit Mac build the same arithmetic addresses somewhere four gigabytes away, and the game dies.

The fix adds the bounds check the original is missing, in the sixteen bytes the function already
occupies — so nothing else in the file moves:

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

Returning `false` is the correct answer — "have we met nobody?" is no — and it's what the game's own
correctly-written code does a few hundred lines earlier. Behaviour for every valid index is unchanged.

Patching invalidates Aspyr's code signature, so the script re-signs the file ad-hoc. Without that,
macOS won't load it.

## Doing it by hand

If you'd rather not run someone else's script — reasonable — it's sixteen bytes in one file:

1. Open `~/Library/Application Support/Steam/steamapps/common/Sid Meier's Civilization V/Civilization V.app/Contents/MacOS/libCvGameCoreDLL_Expansion2_DLL.dylib` in a hex editor.
2. Search for the byte sequence `55 48 89 E5 89 F0 8A 84 07 38 07 00 00 5D C3`. There is exactly one
   match. If you find zero or more than one, stop — you have a build this fix hasn't been tested on.
3. Replace those 15 bytes and the `90` immediately after them with
   `31 C0 85 F6 78 09 89 F0 8A 84 07 38 07 00 00 C3`.
4. Save, then run `codesign --force --sign - "<that same path>"` in Terminal.

Back the file up first.

## Is this safe?

Judge for yourself rather than taking my word:

- The script is ~190 lines and deliberately readable. Read it before you run it.
- It doesn't download anything, doesn't need admin rights, and asks for no passwords.
- It locates the function by byte signature rather than a fixed position, and **refuses to write
  anything unless it finds exactly one match** — so it can't mangle a version it doesn't recognise.
- It backs the original up before touching it, and restores the backup automatically if any step fails.
- Everything in the write-up is independently checkable: Firaxis released the rules-engine source
  publicly, and `objdump` will show you the same function on your own machine.

**Don't install a patched game file from a stranger** — including from me. That's why this ships as a
script that edits your own copy, and not as a replacement binary.

## Credits

The symptom has been known for years. [Rebuild Original
Capital](https://forums.civfanatics.com/threads/mod-rebuild-original-capital-crash-bug-workaround-for-mac.690850/)
is a Lua mod that works around the crash for the direct-occupation case, written well before this
existed.

## Licence

MIT. See `LICENSE`.
