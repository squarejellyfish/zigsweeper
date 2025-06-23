# Zigsweeper

Minesweeper rewritten in Zig.

* **Multiple Skins**
  * RTX
  * Among Us
* **Customizable**
* **Scalable Board**
* **Cheat Mode**
  * Show best starting position
  * Immortal mode
  * Revivable mode

[RTX sprite](https://www.spriters-resource.com/custom_edited/minesweepercustoms/sheet/180218/) by RockPaperKatana. Licensed under CC BY-SA.

The game uses the [Raylib binding for Zig](https://github.com/Not-Nik/raylib-zig.git) for rendering textures, [rlImGui](https://github.com/raylib-extras/rlImGui.git), and [zgui](https://github.com/zig-gamedev/zgui.git) for GUI rendering.

Built and tested on Linux and macOS. It should also work on Windows.

## Building

Requires Zig 0.14.

```bash
$ zig build run
```

## Note

This rewrite was created for casual play and personal use, not for competitive speedrunning. Several features are tailored to my own preferences.
For speedrunning, I still recommend using [Arbiter](https://minesweepergame.com/download/arbiter.php).

## Licenses

Shield: [![CC BY-SA 4.0][cc-by-sa-shield]][cc-by-sa]

The [RTX artwork](./assets/minesweeper-sprite-rtx-1024.png) is licensed under a
[Creative Commons Attribution-ShareAlike 4.0 International License][cc-by-sa].

[![CC BY-SA 4.0][cc-by-sa-image]][cc-by-sa]

[cc-by-sa]: http://creativecommons.org/licenses/by-sa/4.0/
[cc-by-sa-image]: https://licensebuttons.net/l/by-sa/4.0/88x31.png
[cc-by-sa-shield]: https://img.shields.io/badge/License-CC%20BY--SA%204.0-lightgrey.svg

Without the RTX artwork, the code is licensed under The MIT License.
