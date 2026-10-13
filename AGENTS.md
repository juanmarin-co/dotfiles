# AGENTS.md

This repository stores dotfiles using Git and GNU Stow. Each top-level folder is a package that mirrors paths in `$HOME` using symlinks.

Prefer default settings whenever possible. Add configurations only when the user asks for them, or when a tool requires an explicit config file to work. Keep files lean and focused on what is actually in use. Always use the `dependency-docs` skill to verify options, starting with local `man` pages and `--help`.

To add a tool, mirror its path under a package folder and link it with `stow <package>`. Always ask the user before running `git commit`.

## Tools of Interest

| Tool | Homepage / Docs | Git Repository |
| :--- | :--- | :--- |
| Niri | [niri-wm.github.io/niri](https://niri-wm.github.io/niri/) | [YaLTeR/niri](https://github.com/YaLTeR/niri) |
| Waybar | [github.com/Alexays/Waybar](https://github.com/Alexays/Waybar) | [Alexays/Waybar](https://github.com/Alexays/Waybar) |
| Fuzzel | [codeberg.org/dnkl/fuzzel](https://codeberg.org/dnkl/fuzzel) | [dnkl/fuzzel](https://codeberg.org/dnkl/fuzzel) |
| Mako | [mako-project.org](https://mako-project.org/) | [emersion/mako](https://github.com/emersion/mako) |
| swaybg | [github.com/swaywm/swaybg](https://github.com/swaywm/swaybg) | [swaywm/swaybg](https://github.com/swaywm/swaybg) |
| swaylock | [github.com/swaywm/swaylock](https://github.com/swaywm/swaylock) | [swaywm/swaylock](https://github.com/swaywm/swaylock) |
| swayidle | [github.com/swaywm/swayidle](https://github.com/swaywm/swayidle) | [swaywm/swayidle](https://github.com/swaywm/swayidle) |
| grim | [sr.ht/~emersion/grim](https://sr.ht/~emersion/grim/) | [emersion/grim](https://github.com/emersion/grim) |
| slurp | [sr.ht/~emersion/slurp](https://sr.ht/~emersion/slurp/) | [emersion/slurp](https://github.com/emersion/slurp) |
| Satty | [github.com/gabm/satty](https://github.com/gabm/satty) | [gabm/satty](https://github.com/gabm/satty) |
| Ghostty | [ghostty.org](https://ghostty.org/) | [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) |
| Zsh | [zsh.org](https://www.zsh.org/) | [zsh-users/zsh](https://github.com/zsh-users/zsh) |
| Oh My Zsh | [ohmyz.sh](https://ohmyz.sh/) | [ohmyzsh/ohmyzsh](https://github.com/ohmyzsh/ohmyzsh) |
| Herdr | [herdr.dev](https://herdr.dev/) | [herdrdev/herdr](https://github.com/herdrdev/herdr) |
| Pi Coding Agent | [pi.dev](https://pi.dev/) | [earendil-works/pi](https://github.com/earendil-works/pi) |
