# MaliMusicPlayer

Your music. Your adventures. Your soundtrack.

MaliMusicPlayer is a World of Warcraft add-on for playing your own music while you play. Drop your MP3s into the included music folder, run the library updater, and head into Azeroth with your own soundtrack.

## Getting started

### 1. Install the add-on

Exit World of Warcraft and extract the release archive. Copy the included add-on folder into the `Interface\AddOns` directory for the version of WoW you play.  (at time of release, this only supports `_anniversary_' but I will certainly port it to Forever and thus likely retail as the modern API is pretty much the same thing there)

```text
World of Warcraft/
└── _anniversary_/
    └── Interface/
        └── AddOns/
            └── MaliMusicPlayer/
                ├── mp3  (add your music here)
```

### 2. Add your MP3s

Copy your music into the mp3 folder within the `~/AddOns/MaliMusicPlayer/` folder.

Your music is not bundled with the project—you bring your own collection.

### 3. Run the library updater

Double-click `UpdateLibrary.cmd` in the extracted add-on folder.

This Windows launcher runs the included PowerShell library generator, which builds the track list the add-on reads. WoW API limitations require this step, and there is no seek/resume/pause features due to this.  It just plays your music in place of the bgm.

Run it again whenever you add, remove, rename, or move music files. Copying songs into the folder alone does not update the library.

If Windows or PowerShell reports an error, read the message before changing security settings. Include that message when reporting a problem.

### 4. Launch WoW and play

Start World of Warcraft and check that the add-on is enabled in the AddOns menu at character selection. Enter the game, open the player, and choose your music.

Make sure sound and music are enabled in WoW, with the music volume turned up.

## Everyday use

The basic workflow is simple:

```text
Add MP3s → Run UpdateLibrary.cmd → Launch WoW → Play
```

When changing your collection, close WoW first, update your files, run the updater, then launch the game again. Use a full restart after adding audio files rather than relying only on `/reload`.  That said, `/reload` works more often than not.

Renaming or removing a file can and will break the playlist.

## Troubleshooting

### The add-on is missing from the AddOns list

Check that you installed it in the correct WoW game directory. Also check for an extra folder level created during extraction: the `.toc` file should be directly inside the installed add-on folder.

### The library is empty or songs are missing

Check that your MP3s are in the supplied music folder. Run `UpdateLibrary.cmd`, let it finish, and fully restart WoW.

### A song is listed but will not play

Make sure the file has not been moved, renamed, or deleted since you generated the library. Run the updater again after any changes, then restart the game.

Check WoW's sound, music, and volume settings as well.

### The updater fails

Extract the archive before running the launcher. Do not run it from inside the ZIP, and do not separate it from its supporting files.

When reporting an updater problem, include the actual error text rather than only saying that the window closed or the update failed.

## Updating

Back up your music before replacing an existing installation. Preserve your collection when extracting a new release, then regenerate the library before launching WoW.

## Reporting a problem

Include:

- Your WoW version and add-on version.
- What you were doing when the problem occurred.
- What you expected and what happened instead.
- Any Lua error or library-generator error text.
- Steps that reproduce the issue, if possible.

There is no need to upload your personal music collection with a report.

## Credits

ZiRRuSH  
Mali Gnosis  
Malignosis
Infernia
(all these are me)

## License

Released under the MIT License. See `LICENSE.MD` for the full terms.

Use it, change it, share it. Keep the copyright and license notice with copies or substantial portions of the software.

The project's license applies to its code, not to music you add to it.
