# Civilization V Mac fix: crossplay with Windows, and 2 bundled crash fixes

This is a small script for the Steam version of Civilization V on macOS. It does two separate things:

- **Lets a Mac play multiplayer with Windows players.** This stopped working in 2019, when the Mac
  version became 64-bit.
- **Fixes two crashes** that only happen on the Mac. One happens whenever a civilization regains its
  original capital. The other happens when a city-state is liberated.

The script doesn't change any gameplay. The fixes for the crashes add two checks in the game's compiled code that should always have been there, and enabling crossplay with Windows machines takes one line of text. The script is set up so it's very easy to undo the changes, and running 'Verify integrity of game files' in Steam will always reset your files to their initial state. It doesn't download anything, and it never asks for a password or admin rights.

Write-up of the capital crash: <https://arthurthiele.com/writing/civ-v-capital-crash/>

This should work for any Mac running macOS Catalina (2019) or later, Intel or Apple Silicon.

---

## How to use this

**1.** Download [`civ5-mac-fix.sh`](civ5-mac-fix.sh): click the link, then the download button. It
will land in your Downloads folder.

**2.** Quit Civilization V if it is running.

**3.** Open **Terminal** (press `Cmd`+`Space`, type `Terminal`, press Enter), then copy this line,
paste it into the Terminal window, and press Enter:

```
bash ~/Downloads/civ5-mac-fix.sh
```

You should see this, followed by a short note on how to switch multiplayer back:

```
Found Civilization V. Original backed up alongside it.
Fixed: capital recapture crash.
Fixed: city-state stance crash.
File re-signed so macOS will load it.

Multiplayer: set to play with Windows.
```

Start the game. Both crashes are fixed, and you can host or join multiplayer games with
Windows players.

One thing changes that you should know about: while set up this way, your Mac **can't join Macs that
haven't run this script**. See [Playing with unmodified Macs](#playing-with-unmodified-macs) below.

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

Nothing more to do. The Windows player does not need to install or change anything. You can host or join a
multiplayer game as usual.

**A brand-new game with Windows corrects itself once, near the end of the first turn.** The Mac and
Windows versions generate different maps from the same settings, sometimes making the map look completely different. The game notices, pauses briefly, and gives the joining player the host's map. After that the
two stay in step.

To skip that entirely: 
- **the host should save on the very first turn before anyone moves,** 
- **everyone leaves,**
- **the host reloads the game from that save and everyone rejoins**. 

A loaded game gives everyone the host's map from the start.
This isn't essential, and the game will proceed as normal after the resync. But I strongly recommend reloading, so that players don't get attached to a start that they won't get, and so they don't make early-game decisions based on incorrect info. 

## Playing with unmodified Macs

The game only lets players connect when they report the same version, and a Mac can report either
the Mac one or the Windows one, not both. So a Mac set up to play with Windows can also play with
other Macs that have run this script, but not with Macs that haven't.

To play with unmodified Macs, keeping the crash fixes:

```
bash ~/Downloads/civ5-mac-fix.sh --play-with macs
```

And to go back to playing with Windows:

```
bash ~/Downloads/civ5-mac-fix.sh --play-with windows
```

You can switch this whenever you want, and it won't disable the fixes for the crashes.

### What I've tested so far

- A 146-turn game between a Mac and a Windows PC, with AI civilizations and city-states, with no
  problems after the first-turn correction described above.
- Hosting from both the Mac and the Windows machines, up to about 5 turns into the games.
- A Mac with the capital fix playing an unmodified Mac, using `--play-with macs`.

So far, I've only tested over a local network. Playing over the internet through Steam should work the same
way, but I have not yet tested it. Games with mods are untested too. If you try either,
I would like to hear how it goes.

## Undoing it

```
bash ~/Downloads/civ5-mac-fix.sh --undo
```

That removes the crash fixes and sets multiplayer back to how the game shipped. Steam's **Verify integrity of game files**
also restores everything, and any game update will undo it as well. Run the script again afterwards.

## How it works

The script is short and written to be read. What it changes byte by byte, how to do the same thing by
hand, and how to check it for yourself are in [HOW-IT-WORKS.md](HOW-IT-WORKS.md).
