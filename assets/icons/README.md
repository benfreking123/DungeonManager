# Icons test

Planned: one atlas for room stamps + UI glyphs.

Keep icons high-contrast and simple for readability at a glance.

## Best practice for this project (recommended)

Use **one PNG as the source atlas**, then create **one `AtlasTexture` `.tres` per icon** (each `.tres` points at the same PNG but with a different `region`).

- **Pros**: single source file, consistent import settings, easy to reuse in UI + scenes, no duplicated PNGs.
- **Cons**: you define regions once (but that’s a one-time cost).

In Godot, an `AtlasTexture` is effectively “a slice of a texture”. There isn’t a single resource that stores *many named slices*—the idiomatic approach is “many small `AtlasTexture` resources that all reference the same PNG”.

## What you have right now

- `ChatGPT Image Jan 14, 2026, 12_39_41 PM.png`: the source atlas image
- `icon_atlas.tres`: currently **one** `AtlasTexture` slice (one `region`) of that PNG

To “slice it into individual icons”, you’ll create **more** `AtlasTexture` `.tres` files (one per class/monster/boss icon).

## Step-by-step: create per-icon slices (`AtlasTexture` resources)

1. **Confirm import settings on the PNG**
   - In the FileSystem dock, click the PNG.
   - In the Import dock:
	 - Keep **Mipmaps = Off** (good for UI).
	 - Keep **Fix Alpha Border = On** (helps avoid edge bleeding on atlases).
	 - Compression: for UI, **Lossless / VRAM uncompressed** is usually fine; if you later see memory issues, revisit.

2. **Create a new `AtlasTexture` resource**
   - Right-click `assets/icons/` (or make a folder like `assets/icons/slices/`)
   - **New Resource…** → choose **AtlasTexture**
   - Save it with a clear name, e.g.:
	 - `icon_class_mage.tres`
	 - `icon_class_rogue.tres`
	 - `icon_monster_zombie.tres`
	 - `icon_boss_lichking.tres`

3. **Set the atlas + region**
   - Select your new `.tres`.
   - In the Inspector:
	 - Set **atlas** → your PNG
	 - Set **region** → pick the rectangle for that icon
	   - You can type values (Rect2: x, y, w, h), or use the region picker UI.

4. **Repeat for each icon**
   - You’ll end up with a folder full of `icon_*.tres` resources, all referencing the same PNG.

## How to use the icons (UI + scenes)

- **Buttons**: set the Button’s **Icon** property to an `AtlasTexture` `.tres`.
  - Optional: enable **Expand Icon** if you want consistent sizing.
- **TextureRect**: set the **Texture** property to the `.tres`.

This project’s current UI (`ui/InventoryBar.tscn`) uses plain `Button`s; adding icons is as simple as assigning each button’s `icon` in the inspector (no code required).

## When *not* to use an atlas (when separate PNGs are OK)

Make individual icon PNGs if:
- you want totally different import settings per icon (filtering, mipmaps, compression),
- you’re using an external pipeline that already outputs separate images,
- you frequently edit/re-export a single icon and don’t want to manage atlas coordinates.

Otherwise, the **atlas + per-icon `AtlasTexture` `.tres`** approach will be the cleanest/lowest-friction option in Godot.

## Optional (later): a tiny “icon registry”

If you start referencing icons by string ids in code (ex: `"zombie"`), consider adding a small autoload like `autoloads/IconDB.gd` that preloads `res://assets/icons/slices/icon_*.tres` and provides `get_icon(id)`. It’s not necessary to start—using the inspector is simplest until you feel repetition pain.
