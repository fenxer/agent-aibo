---
name: hatch-aibo
description: Generate V2 aibo/Codex pets as guttered animation strips, then shared-camera clips plus an 8x11 spritesheet. About 10–12 image gens per run (not per-frame). Ask the user about per-state action overrides and image-gen host before generating. Use when the user wants a custom aibo pet, hatch-aibo, Petdex V2 atlas, or to replace hatch-pet connected-component slicing.
---

# Hatch Aibo

Generate a **V2** aibo / Petdex pet: `clips/` + `aibo.json` first, then `pet.json` + `spritesheet.webp`.

**Cost: ~10 gens for V1, ~12 for V2** (close to old hatch-pet). Do not generate per frame. Default **V2**; do not ask which version unless the user specifies.

```text
SKILL_DIR="<repo>/Skills/hatch-aibo"
```

Phase tables: [references/phases.md](references/phases.md). Atlas format: [references/atlas-contract.md](references/atlas-contract.md).

Deps: `pip install -r Skills/hatch-aibo/requirements.txt`

---

## User-facing

Ask the items below before generating. Skip anything already clear from the current message (name, attached reference). **Do not ask V1 vs V2** — default 2. Use `--atlas-version 1` only when the user explicitly wants animation without look.

### Intake

1. **Name**, **appearance** (may infer from a reference), **reference image** (optional), **style** (optional, default `flat-vector`).
2. **Whether each action needs a custom description.** Show the default lines below. Ask: use all defaults, or override specific rows. Unmentioned states keep defaults. Overrides replace the action sentence only — not the crossover gait or look facing table.

| Row | State | Default action |
| ---: | --- | --- |
| 0 | idle | Quiet standing: slight breathing or blink. Feet planted. No walk, wave, jump, or new props. |
| 1 | running-right | Profile run to the right. Legs must cross: among 8 frames, both right-foot-forward and left-foot-forward. |
| 2 | running-left | Do not generate. Assemble mirrors running-right. |
| 3 | waving | One paw/hand greeting. No motion lines or sparkles. |
| 4 | jumping | Jump: crouch → airborne (shins up, knees bent) → land back to stand. Same scale; do not enlarge. |
| 5 | failed | Blocked/sad: squat, slump, droop. No floating X marks. |
| 6 | waiting | Expectant, waiting for approval. Not idle, not review. |
| 7 | running | **Work** (think / type / aim), not locomotion. Feet planted. |
| 8 | review | Inspect finished work: head tilt, blink, chin pinch. No new props. |
| 9–10 | look | Standing full body; only facing changes. No walk cycle. |

3. **How to generate images.** Detect a host in this environment: Cursor `GenerateImage` tool, Codex `$imagegen`, or an installed image-gen skill. If one exists, tell the user which you will use and ask if they want a different one. **If none exist, stop and ask**: user-supplied images, an external API, or prepare-only. Scripts never call image APIs.

Do not `prepare` or generate until (2) and (3) are answered.

### After the run

Point at `qa/contact-sheet.png` (and `qa/previews/*.gif`). Speak in **row numbers**. Tell the user: if a row is wrong, name the row; only that strip is redrawn.

| Row | Job to redo |
| ---: | --- |
| 0 idle | `idle` |
| 1 running-right | `running-right-a` and/or `running-right-b` |
| 2 running-left | Edit the right strip; assemble mirrors it |
| 3 waving | `waving` |
| 4 jumping | `jumping` |
| 5 failed | `failed` |
| 6 waiting | `waiting` |
| 7 running (work) | `running` |
| 8 review | `review` |
| 9 look 00–07 | `look-a` |
| 10 look 08–15 | `look-b` |

Do not rerun all 12 gens because one row is wrong.

Outputs: `run/final/aibo.json`, `clips/`, `pet.json`, `spritesheet.webp`.

---

## Skill-internal

Do not ask the user about this. Follow it yourself.

### Image count

| Version | Gens | Contents |
| --- | ---: | --- |
| V1 | 10 | 1 base + one strip each for idle / wave / jump / failed / waiting / work / review + **2** running-right strips (first 4 / last 4 crossover) |
| V2 (default) | 12 | V1 + look 00–07 and 08–15 |

Do not generate `running-left`. Geometry: leave large chroma gutters between slots at gen time; assemble splits on 1D gaps, then shared camera. Do not generate a full atlas in one shot, and do not generate 60+ per-frame images.

### 1. Prepare

Pass user action overrides as repeated `--state-prompt 'state=...'`.

```bash
python "$SKILL_DIR/scripts/prepare_pet_run.py" \
  --pet-name "<Name>" \
  --pet-notes "<stable identity>" \
  --reference /abs/ref.png \
  --atlas-version 2 \
  --output-dir /abs/run
```

`generation_images` should be 10 or 12. `ready` = incomplete and dependencies complete.

### 2. Generate (one strip per job)

1. Read `prompt_file`. Reference images: only `canonical-base` / character refs / the previous run strip (`running-right-b` must include a). **Do not pass layout-guide or stage-guide as `reference_image_paths`** — the model will paint the boxes into the strip. Slot count, gutters, and horizon go in the prompt.
2. One landscape image: exactly N full-body poses, **at least one-head-width of pure chroma between poses**, no overlap, no wrap, props stay in slot.
3. Copy to `output_path` and mark complete:

```bash
JOB_ID=idle
SOURCE=/abs/generated.png
OUTPUT=$(jq -r --arg id "$JOB_ID" '.jobs[] | select(.id==$id).output_path' "$RUN/imagegen-jobs.json")
mkdir -p "$(dirname "$RUN/$OUTPUT")"
cp "$SOURCE" "$RUN/$OUTPUT"
# If JOB_ID=base also: cp "$RUN/$OUTPUT" "$RUN/references/canonical-base.png"
jq --arg id "$JOB_ID" --arg src "$SOURCE" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '(.jobs[] | select(.id==$id)) += {status:"complete", source_path:$src, completed_at:$at}' \
  "$RUN/imagegen-jobs.json" > /tmp/jobs.json && mv /tmp/jobs.json "$RUN/imagegen-jobs.json"
```

Order: `base` → `idle` and `running-right-a` → `running-right-b` (must include a) → remaining action strips → V2 `look-a` then `look-b`. At most 2 in parallel.

Hosts often squash strips to ~1536 wide. **8-slot strips (`failed`, `look-a`/`look-b`) wrap on equal-split if gutters are too thin.** Prompt for small figures + large green gaps. On failure, redraw that strip; do not switch image models as the first fix.

### 3. Assemble

```bash
python "$SKILL_DIR/scripts/assemble_pet.py" --run-dir /abs/run
```

Key chroma (including green-edge despill), split on gutters, shared camera, mirror running-left, write clips / webp / contact / GIFs / `aibo.json` / `pet.json`.

No connected-component strip cuts. No per-frame `fit_to_cell` (squats zoom in). Standing rows identity-match hat-to-foot to one target height. `failed` / `running-right` / `jumping` **share one scale per state** (from the tallest frame); poses get shorter — do not fill the cell per frame. Equal-split only when there are no gaps, and log a warning.

A full `assemble` rebuilds all fitted frames from `decoded/`. If look 05–07 were mirrored, **either fix source strip `look-a`, or remirror those three frames after assemble**. Assembling other rows wipes those mirrors.

### 4. QA

Inspect `qa/contact-sheet.png` and `qa/previews/*.gif`. On failure, redraw **that one strip**:

- Fragments on both sides of a slot (wrap)
- Body or gun cut off
- `running-right` missing both left-foot-forward and right-foot-forward
- Size / foot plant jumping; standing hat-to-foot misaligned
- Guide boxes painted into the strip
- Wrong look facing (0=up/back, 4=right, 8=front, 12=left). **05–07 often face right; if they should keep facing left, mirror only those three frames.**
- Run feet past the cell bottom

### Rules

- Lock identity to canonical base; action = default phases + optional user action sentence.
- Wide props stay inside the slot; do not draw off-slot then wrap to the other side.
- `running` is work, not locomotion.
- Green fringes are a chroma despill problem, not a reason to switch image models.
