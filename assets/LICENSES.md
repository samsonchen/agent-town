# Asset licenses

Every asset in this repository, where it comes from, and its license.

| Path | Source | Version | License |
|---|---|---|---|
| `assets/kenney/mini-characters/` | [Kenney Mini Characters](https://kenney.nl/assets/mini-characters-1) | 1.0 (2024-07-17) | CC0 1.0. See `License.txt` in the folder. |
| `assets/kenney/furniture-kit/` | [Kenney Furniture Kit](https://kenney.nl/assets/furniture-kit) | 2.0 (2018-10-20) | CC0 1.0. See `License.txt` in the folder. |
| `assets/models/characters/` | Generated from `assets/kenney/mini-characters/` by `tools/convert-assets.py` | | CC0 1.0 (derived) |
| `assets/models/furniture/` | Generated from `assets/kenney/furniture-kit/` by `tools/convert-assets.py` | | CC0 1.0 (derived) |
| `app/windows/shared/` | Copies for the Windows app (Godot loads only files inside its project), made by `tools/sync-windows-assets.py` from `assets/kenney/`, `catalog/` and the macOS app's strings | | As their sources: the Kenney models CC0 1.0, the rest Apache 2.0 |
| `app/windows/fonts/Cubic_11.ttf` | [Cubic 11 (俐方體11號)](https://github.com/ACh-K/Cubic-11) | 1.500 | SIL Open Font License 1.1, with `OFL.txt` beside it. Not sold on its own; a modified font may not use the names "Cubic" or "俐方體". |
| `assets/icons/app-icon-1024.png` | The app icon, made by Samson Chen for agent-town | 2026-11-11 | Apache 2.0, as the rest of this repository. See `LICENSE`. |

Only the models the app uses are copied from each pack. Credit is not required by CC0. We credit Kenney (www.kenney.nl) anyway.

To regenerate `assets/models/`, run from the repository root:

```bash
blender -b --python tools/convert-assets.py
```
