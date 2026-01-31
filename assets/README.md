# Assets (Blueprint Pixel Pipeline)

We’re targeting an abstract “blueprint” look with **32x32** tiles and simple icon stamps.

## Recommended texture settings (Godot Import tab)

For any pixel-art `.png` used in-game (icons, tiles, units):
- **Filter**: Off (Nearest)
- **Mipmaps**: Off
- **Repeat**: Disabled (unless explicitly needed)
- **Compression Mode**: Lossless (or VRAM uncompressed for UI if needed)

Project defaults are also set in `project.godot` to use nearest-neighbor for Canvas textures.

## Suggested structure
- `assets/icons/` room stamps + UI glyph atlas
- `assets/tiles/` (optional) minimal tileset primitives if we move from procedural lines to tiles
- `assets/fonts/` (optional) pixel font
