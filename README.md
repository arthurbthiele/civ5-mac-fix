# Civilization V Mac fix: two crashes, and multiplayer with Windows

A small script for the Steam version of Civilization V on macOS. It does two separate things:

- **Fixes two crashes** that only happen on the Mac. One hits whenever a civilization regains its
  original capital. The other hits when a city-state is liberated back into the game.
- **Lets a Mac play multiplayer with Windows players.** This stopped working in 2019, when the Mac
  version became 64-bit. It is off unless you switch it on.

It changes no gameplay. The crash fixes add two checks the game's code is missing, and the multiplayer
switch changes one line of text. Everything can be undone.

Write-up of the capital crash: <https://arthurthiele.com/writing/civ-v-capital-crash/>

For any Mac running macOS Catalina (2019) or later, Intel or Apple Silicon.

---

## Just fix it

**1.** Download [`civ5-mac-fix.sh`](civ5-mac-fix.sh): click the link, then the download button. It
will land in your Downloads folder.

**2.** Quit Civilization V if it is running.

**3.** Open **Terminal** (press `Cmd`+`Space`, type `Terminal`, press Enter), then copy this line,
paste it into the Terminal window, and press Enter:

```
bash ~/Downloads/civ5-mac-fix.sh
```

You should see:

```
Found Civilization V. Original backed up alongside it.
Fixed: capital recapture crash.
Fixed: city-state stance crash.
File re-signed so macOS will load it.
```

That's it for the crashes. Start the game and load your save.

**Want to look before changing anything?** This reports what state your game is in and changes
nothing:

```
bash ~/Downloads/civ5-mac-fix.sh --check
```

**If it can't find your game** (a Steam library on an external drive, say), point it at the app:

```
bash ~/Downloads/civ5-mac-fix.sh --path "/path/to/Civilization V.app"
```

## Playing with Windows

Switch crossplay on:

```
bash ~/Downloads/civ5-mac-fix.sh --crossplay on
```

The Windows player does not need to install or change anything. Host or join a multiplayer game as
usual, from either side.

Two things to know before you do:

- **While crossplay is on, you can't join Macs that have it off.** The game only lets players
  connect when they report the same version, and a Mac can report either the Mac one or the Windows
  one, not both. To play with unmodified Macs again, switch back:

  ```
  bash ~/Downloads/civ5-mac-fix.sh --crossplay off
  ```

- **A brand-new crossplay game corrects itself once, near the end of the first turn.** The Mac and
  Windows versions generate very slightly different maps from the same settings, usually a tile or
  two. The game notices, pauses briefly, and gives the joining player the host's map. After that the
  two stay in step. Until it happens, the joining player may be looking at a tile that is about to
  change, so it is worth not committing to anything on turn one.

  To skip that entirely: the host saves on the very first turn before anyone moves, everyone leaves,
  and the host starts the game again with **Load Game**. A loaded game hands everyone the host's map
  from the start.

### What has been tested

- A 146-turn game between a Mac and a Windows PC, with AI civilizations and city-states, with no
  problems after the first-turn correction described above.
- Hosting from the Mac and hosting from Windows.
- A Mac with the capital fix playing an unmodified Mac (with crossplay off).

All of that was over a local network. Playing over the internet through Steam should work the same
way, but I have not been able to test it. Games with mods are untested too. If you try either,
I would like to hear how it goes.

## Undoing it

```
bash ~/Downloads/civ5-mac-fix.sh --undo
```

That removes the crash fixes and switches crossplay off. Steam's **Verify integrity of game files**
also restores everything, and any game update will undo it as well. Run the script again afterwards.

## What it actually changes

### The capital crash

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

### The city-state crash

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

### The crossplay switch

Civilization V only lets players connect when they announce the same build number. Windows announces
`403694`. The Mac build runs the same rules, but announces Aspyr's own number, `180925`, which it
takes from one line in a text file inside the app:

```
Contents/AspyrAssets/global/String/App.json

before:  "App.WinFileVersionStr" : "{App.WinFileVersion} ({App.Build})",
after:   "App.WinFileVersionStr" : "{App.WinFileVersion} (403694)",
```

That one line is the whole switch. No program code changes for crossplay.

## Doing it by hand

If you would rather not run someone else's script, which is reasonable, everything above is enough
to do it yourself:

1. Back up `Civilization V.app/Contents/MacOS/libCvGameCoreDLL_Expansion2_DLL.dylib`, then open it
   in a hex editor.
2. Search for each "before" byte sequence. Each has exactly one match. If you find none, or more than
   one, stop: you have a build this has not been tested on.
3. Replace each with its "after" sequence, save, and run
   `codesign --force --sign - "<path to that file>"` in Terminal.
4. For crossplay, edit the line in `App.json` shown above with any text editor.

## Is this safe?

Judge for yourself:

- The script is about 330 lines and written to be read. Read it before you run it.
- It downloads nothing, needs no admin rights, and asks for no passwords.
- It finds each place to patch by its exact bytes and **refuses to write anything unless it finds
  exactly one match**, so it can't mangle a version it doesn't recognise.
- It backs up the original library first, and `--undo` puts things back.
- It never touches the game's main program, only the rules library and one text file.
- Everything here is independently checkable: Firaxis released the rules-engine source publicly, and
  `objdump` will show you the same functions on your own machine.

**Don't install a patched game file from a stranger**, including from me. That is why this is a
script that edits your own copy, and not a replacement file.

## Credits

The capital crash has been known for years. [Rebuild Original
Capital](https://forums.civfanatics.com/threads/mod-rebuild-original-capital-crash-bug-workaround-for-mac.690850/)
is a Lua mod that works around it for the direct-occupation case, written well before this existed.

## Licence

MIT. See `LICENSE`.
