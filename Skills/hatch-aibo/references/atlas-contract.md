# Atlas and package contract

Cell is always `192×208`. Columns are always 8.

| Version | Rows | Pixel size | Extra |
| --- | ---: | --- | --- |
| 1 | 9 | `1536×1872` | animation only |
| 2 (default) | 11 | `1536×2288` | rows 9–10 are 16 look cells |

## Animation rows (0–8)

| Row | State | Frames | Loop ms |
| ---: | --- | ---: | ---: |
| 0 | idle | 6 | 1100 |
| 1 | running-right | 8 | 1060 |
| 2 | running-left | 8 | 1060 |
| 3 | waving | 4 | 700 |
| 4 | jumping | 5 | 840 |
| 5 | failed | 8 | 1220 |
| 6 | waiting | 6 | 1010 |
| 7 | running (work, not locomotion) | 6 | 820 |
| 8 | review | 6 | 1030 |

Unused cells in a row stay fully transparent. Transparent pixels must have RGB 0.

## Look rows (V2)

16 stills, clockwise from up, 22.5° steps. Index `i` lives at row `9 + i/8`, column `i%8`.

aibo stores them as `clips/look-00.png` … `look-15.png`, not as a 16-frame strip.

## `final/aibo.json`

```json
{
  "format": "aibo",
  "formatVersion": 1,
  "sliceVersion": 1,
  "extends": "petdex-v2",
  "cellWidth": 192,
  "cellHeight": 208,
  "clips": {
    "idle": {"file": "clips/idle.png", "frames": 6, "durationMilliseconds": 1100}
  },
  "look": [{"index": 0, "file": "clips/look-00.png"}]
}
```

`extends` is `petdex-v1` when `--atlas-version 1`.

## `final/pet.json`

```json
{
  "id": "slug",
  "displayName": "Name",
  "description": "One sentence.",
  "spritesheetPath": "spritesheet.webp",
  "spriteVersionNumber": 2
}
```

## Geometry rules for assemble

- Generate guttered strips (empty chroma between poses). Split by 1D occupancy gaps, never 2D connected components.
- Then apply one shared camera: one scale, body-center X, planted baseline (jumping uses the stage ground line).
- `running-left` is a horizontal mirror of each already-fitted `running-right` cell.
- Budget: V1 = 10 generated images, V2 = 12. Do not generate one image per frame.
