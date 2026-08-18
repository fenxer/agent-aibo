# Default phase tables

Generation is **one guttered strip per job**, not one image per frame. `running-right` is two strips of 4 so the second half can be forced to swap feet. `running-left` is a mirror after shared-camera fit.

User `--state-prompt` replaces the **action sentence** only. Per-slot phases below still go into the strip prompt unless the user explicitly asks for non-walk locomotion.

## idle — 6 frames, keys 00 / 02 / 05

Calm. Feet locked. Props fully inside the safe box.

| Frame | Role | Phase |
| --- | --- | --- |
| 00 | key | Neutral rest, eyes open. Loop start. |
| 01 | inbetween | Toward the quiet variation. Feet locked. |
| 02 | key | Blink or tiny breath. Legs/props locked to 00. |
| 03 | inbetween | Returning. |
| 04 | inbetween | Almost rest. |
| 05 | key | Loop end, very close to 00. |

## running-right — 8 frames, keys 00 / 02 / 04 / 06

Face and travel **right**. Frames 00 and 04 must swap which foot is planted in front.

| Frame | Role | Phase |
| --- | --- | --- |
| 00 | key | Contact A: **right** foot front, left foot back. |
| 01 | inbetween | Left leg swinging forward. |
| 02 | key | Passing A: left leg crosses through the middle. |
| 03 | inbetween | Crossover into opposite contact. |
| 04 | key | Contact B: **left** foot front, right foot back. |
| 05 | inbetween | Right leg swinging forward. |
| 06 | key | Passing B: right leg crosses through the middle. |
| 07 | inbetween | Back toward contact A / frame 00. |

## waving — 4 frames, keys 00 / 01 / 03

Limb down → raised peak → return. No motion lines.

## jumping — 5 frames, keys 00 / 02 / 04

Crouch (feet on ground) → peak (feet off ground, **same scale**, body higher) → land. Vertical mode is `stage`.

## failed — 8 frames, keys 00 / 03 / 07

Upright reaction → lowest slump → hold slump. No floating X.

## waiting — 6 frames, keys 00 / 03 / 05

Expectant ask, not idle, not review.

## running — 6 frames, keys 00 / 02 / 05

Working / thinking / typing. **Not** foot-running.

## review — 6 frames, keys 00 / 03 / 05

Inspect, lean, blink, or head tilt. No new props.

## look — 16 stills (V2 only)

Keys every 45°: 00, 02, 04, 06, 08, 10, 12, 14. Odd indices are in-betweens between neighboring keys.

Clockwise from up, matching aibo / petx (`atan2(x, -y)`, y down):

| Index | Degrees | Facing |
| ---: | ---: | --- |
| 00 | 0 | Up / back |
| 04 | 90 | Right profile |
| 08 | 180 | Front, facing camera |
| 12 | 270 | Left profile |
