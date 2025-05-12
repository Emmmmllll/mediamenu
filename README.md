## A Simple Keybind controlled menu to control media playback

# Dependencies
- Playerctl
- Gtk-3.0
- Glib
- Gobject

# Keybinds
Currently only adjustable in the source code in the
handle_key_press function of src/main.zig

Default keybinds: (vim inspired)
```
h = seek back 5 seconds
l = seek forward 5 seconds
<Shift> h = previous track
<Shift> l = next track
<Ctrl> h = previous player  (only with playerctld)
<Ctrl> l = next player      (only with playerctld)
k = play / pause toggle

n = next track (alternative because 'n' in next)
p = previous track (alternative because 'p' in previous)

q = quit
<Esc> = quit
```
Also quits on lost window focus if not launced with `--stay` flag

## Installation
## Build from source
It's dead simple. You need zig installed and run.
```
$ zig build
```
then the executable will be at `zig-out/bin/mediamenu`

## Contribution
The only goal is to have a way to efficiently controll the media player with keybinds. But if there are things that in your opinion should be added, feel free to create a pull request.
