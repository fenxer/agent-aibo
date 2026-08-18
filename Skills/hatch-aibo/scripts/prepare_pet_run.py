#!/usr/bin/env python3
"""Create a hatch-aibo run folder, per-frame prompts, and the imagegen job graph."""

from __future__ import annotations

import argparse
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

from hatch_lib import (
    LOOK_FACING,
    LOOK_STEP_DEGREES,
    STAGE_HEIGHT,
    STAGE_WIDTH,
    STATES,
    STYLE_PRESETS,
    choose_chroma_key,
    create_stage_guide,
    create_strip_guide,
    iter_generation_strips,
    slugify,
)

CANONICAL_BASE = "references/canonical-base.png"
STAGE_GUIDE = "references/stage-guide.png"
LAYOUT_GUIDE_DIR = "references/layout-guides"


def compact(value: str) -> str:
    return " ".join(value.strip().split())


def sentence(value: str) -> str:
    value = compact(value)
    if value and value[-1] not in ".!?":
        value += "."
    return value


def rel(path: Path, root: Path) -> str:
    return str(path.resolve().relative_to(root.resolve()))


def parse_state_prompt_items(items: list[str]) -> dict[str, str]:
    known = {state["id"] for state in STATES}
    known.add("look")
    overrides: dict[str, str] = {}
    for item in items:
        if "=" not in item:
            raise SystemExit(f"--state-prompt must be STATE=text, got: {item}")
        state_id, text = item.split("=", 1)
        state_id = state_id.strip()
        if state_id not in known:
            raise SystemExit(f"unknown state in --state-prompt: {state_id}")
        overrides[state_id] = compact(text)
    return overrides


def load_state_prompts_file(path: str) -> dict[str, str]:
    if not path:
        return {}
    data = json.loads(Path(path).expanduser().read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise SystemExit("--state-prompts-file must be a JSON object of state -> text")
    items = [f"{key}={value}" for key, value in data.items()]
    return parse_state_prompt_items(items)


def style_contract(preset: str, notes: str) -> str:
    if preset not in STYLE_PRESETS:
        raise SystemExit(f"invalid style preset: {preset}")
    contract = (
        "Pet-safe sprite: compact full-body mascot, readable in a 192x208 cell, "
        f"clear silhouette. Style `{preset}`: {STYLE_PRESETS[preset]}"
    )
    if notes.strip():
        contract += f" User style notes: {compact(notes)}."
    return contract


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8")


def shared_rules(chroma_name: str, chroma_hex: str) -> str:
    return f"""Background: perfectly flat pure {chroma_name} {chroma_hex}. No scenery, shadows, floor patches, checkerboard, text, or guide lines.

Identity lock: same face, proportions, clothes, palette, materials, and props as the canonical base.

Do not draw attached guides. Use them only for slot count, gaps, centering, and the ground line."""


def base_prompt(args: argparse.Namespace) -> str:
    return f"""Create one clean full-body reference sprite for aibo pet {args.display_name}.

Pet identity: {args.pet_notes}.
Style: {args.style_contract}

{shared_rules(args.chroma_key["name"], args.chroma_key["hex"])}

Output a single centered standing pose on the chroma background, compact enough to animate, with every prop fully visible inside the safe box."""


def strip_prompt(args: argparse.Namespace, strip: dict[str, object]) -> str:
    state_id = str(strip["state"])
    start = int(strip["start"])
    count = int(strip["count"])
    if state_id == "look":
        action = args.state_prompts.get("look") or (
            "Standing idle body, no walk cycle. Only the facing direction changes."
        )
        slots = "\n".join(
            f"- Slot {offset + 1} = look {start + offset:02d} "
            f"({(start + offset) * LOOK_STEP_DEGREES:g}°): {LOOK_FACING[start + offset]}"
            for offset in range(count)
        )
        extra = ""
        if strip.get("reference_strip"):
            extra = (
                "\nThis is the second look strip (08-15). Keep identity and scale from the "
                "attached first look strip. Continue clockwise; do not restart at up."
            )
        return f"""Create one horizontal strip of exactly {count} standing look poses for aibo pet `{args.pet_id}`.

Identity: {args.pet_notes}.
Style: {args.style_contract}
Look action (user notes override the default sentence): {action}
{extra}

Leave a wide EMPTY chroma gap between poses (at least one head-width). Poses must not overlap, touch, clip, or wrap into the next slot. Every prop stays inside its own slot.

{slots}

Feet planted. Same scale and ground line in every slot.
{shared_rules(args.chroma_key["name"], args.chroma_key["hex"])}"""

    state = next(item for item in STATES if item["id"] == state_id)
    action = args.state_prompts.get(state_id) or str(state["action"])
    phases = list(state["phases"])  # type: ignore[arg-type]
    slots = "\n".join(
        f"- Slot {offset + 1} = frame {start + offset:02d}: {phases[start + offset]}"
        for offset in range(count)
    )
    extra = ""
    if strip.get("id") == "running-right-b":
        extra = (
            "\nThis is the SECOND HALF of the run. The attached first-half strip has the "
            "RIGHT foot forward. These four poses MUST plant the LEFT foot in front "
            "(crossover). Do not repeat the first-half leg order."
        )
    return f"""Create one horizontal animation strip of exactly {count} full-body poses for aibo pet `{args.pet_id}`, state `{state_id}` frames {start:02d}-{start + count - 1:02d}.

Identity: {args.pet_notes}.
Style: {args.style_contract}
State action (user notes override the default sentence): {action}
{extra}

Leave a wide EMPTY chroma gap between poses (at least one head-width). Poses must not overlap, touch, clip, or wrap into the next slot. Every prop, weapon, and limb stays inside its own slot.

Keep the same character scale and ground line in every slot unless this is jumping and the body is intentionally higher.

Mandatory per-slot phases (keep foot order unless the user notes explicitly request hover/slither):
{slots}

{shared_rules(args.chroma_key["name"], args.chroma_key["hex"])}"""


def input_image(path: str, role: str) -> dict[str, str]:
    return {"path": path, "role": role}


def make_jobs(args: argparse.Namespace, copied_refs: list[dict[str, object]]) -> list[dict[str, object]]:
    user_refs = [
        input_image(rel(Path(str(ref["copied_path"])), args.run_dir), "pet reference")
        for ref in copied_refs
    ]
    jobs: list[dict[str, object]] = [
        {
            "id": "base",
            "kind": "base",
            "status": "pending",
            "prompt_file": "prompts/base.md",
            "output_path": "decoded/base.png",
            "depends_on": [],
            "input_images": [
                *user_refs,
                input_image(STAGE_GUIDE, "stage guide for placement only; do not copy lines"),
            ],
        }
    ]
    for strip in iter_generation_strips(args.atlas_version):
        strip_id = str(strip["id"])
        inputs = [
            *user_refs,
            input_image(CANONICAL_BASE, "canonical identity reference"),
            input_image(
                f"{LAYOUT_GUIDE_DIR}/{strip_id}.png",
                "strip layout guide; use for slot count and gaps only, do not copy lines",
            ),
        ]
        if strip.get("reference_strip"):
            ref_id = str(strip["reference_strip"])
            inputs.append(
                input_image(f"decoded/{ref_id}.png", f"previous strip {ref_id} for continuity")
            )
        jobs.append(
            {
                "id": strip_id,
                "kind": "strip",
                "status": "pending",
                "state": strip["state"],
                "start": strip["start"],
                "count": strip["count"],
                "prompt_file": f"prompts/strips/{strip_id}.md",
                "output_path": f"decoded/{strip_id}.png",
                "depends_on": list(strip["depends_on"]),
                "input_images": inputs,
            }
        )
    jobs.append(
        {
            "id": "running-left",
            "kind": "derive",
            "status": "pending",
            "state": "running-left",
            "derive_from": "running-right",
            "depends_on": ["running-right-a", "running-right-b"],
            "prompt_file": None,
        }
    )
    return jobs


def infer_name(args: argparse.Namespace, references: list[Path]) -> str:
    for raw in (args.display_name, args.pet_name):
        if raw.strip():
            return raw.strip()
    if args.pet_id.strip():
        return args.pet_id.replace("-", " ").title()
    for raw in (args.pet_notes, args.description):
        words = compact(raw).split()
        if words:
            return words[0].capitalize()
    if references:
        slug = slugify(references[0].stem)
        if slug:
            return slug.replace("-", " ").title()
    return "Sprout"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pet-name", default="")
    parser.add_argument("--pet-id", default="")
    parser.add_argument("--display-name", default="")
    parser.add_argument("--description", default="")
    parser.add_argument("--reference", action="append", default=[])
    parser.add_argument("--pet-notes", default="")
    parser.add_argument("--style-preset", default="auto", choices=sorted(STYLE_PRESETS))
    parser.add_argument("--style-notes", default="")
    parser.add_argument("--chroma-key", default="auto")
    parser.add_argument("--atlas-version", type=int, default=2, choices=(1, 2))
    parser.add_argument(
        "--state-prompt",
        action="append",
        default=[],
        help="Repeatable STATE=text override. Use look=... for V2 facing frames.",
    )
    parser.add_argument("--state-prompts-file", default="")
    parser.add_argument("--output-dir", default="")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    reference_paths = [Path(path).expanduser().resolve() for path in args.reference]
    args.display_name = infer_name(args, reference_paths)
    args.pet_name = (args.pet_name or args.display_name).strip()
    args.pet_id = slugify(args.pet_id or args.pet_name)
    args.description = sentence(args.description) or sentence(
        f"A compact aibo pet: {args.pet_notes or args.display_name}"
    )
    args.pet_notes = compact(args.pet_notes) or compact(args.description).rstrip(".")
    args.style_contract = style_contract(args.style_preset, args.style_notes)
    args.state_prompts = load_state_prompts_file(args.state_prompts_file)
    args.state_prompts.update(parse_state_prompt_items(args.state_prompt))
    if not args.pet_id:
        raise SystemExit("pet id must contain a letter or digit")

    if args.output_dir:
        run_dir = Path(args.output_dir).expanduser().resolve()
    else:
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        run_dir = Path.cwd() / "output" / "hatch-aibo" / f"{args.pet_id}-{stamp}"
    if run_dir.exists() and any(run_dir.iterdir()) and not args.force:
        raise SystemExit(f"{run_dir} already exists; pass --force to reuse it")
    run_dir.mkdir(parents=True, exist_ok=True)
    args.run_dir = run_dir

    ref_dir = run_dir / "references"
    for directory in (ref_dir, run_dir / "prompts", run_dir / "decoded", run_dir / "qa"):
        directory.mkdir(parents=True, exist_ok=True)

    copied_refs: list[dict[str, object]] = []
    copied_paths: list[Path] = []
    for index, source in enumerate(reference_paths, start=1):
        if not source.is_file():
            raise SystemExit(f"reference not found: {source}")
        copied = ref_dir / f"reference-{index:02d}{source.suffix.lower() or '.png'}"
        shutil.copy2(source, copied)
        copied_refs.append({"source_path": str(source), "copied_path": str(copied)})
        copied_paths.append(copied)

    args.chroma_key = choose_chroma_key(copied_paths, args.chroma_key)
    create_stage_guide(run_dir / STAGE_GUIDE, args.chroma_key["hex"])
    strips = iter_generation_strips(args.atlas_version)
    for strip in strips:
        create_strip_guide(
            run_dir / LAYOUT_GUIDE_DIR / f"{strip['id']}.png",
            int(strip["count"]),
            args.chroma_key["hex"],
        )

    write_text(run_dir / "prompts" / "base.md", base_prompt(args))
    for strip in strips:
        write_text(
            run_dir / "prompts" / "strips" / f"{strip['id']}.md",
            strip_prompt(args, strip),
        )

    jobs = make_jobs(args, copied_refs)
    request = {
        "pet_id": args.pet_id,
        "display_name": args.display_name,
        "description": args.description,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "atlas_version": args.atlas_version,
        "cell": {"width": 192, "height": 208},
        "stage": {"width": STAGE_WIDTH, "height": STAGE_HEIGHT},
        "chroma_key": args.chroma_key,
        "pet_notes": args.pet_notes,
        "style_preset": args.style_preset,
        "style_notes": compact(args.style_notes),
        "style_contract": args.style_contract,
        "state_prompts": args.state_prompts,
        "generation_images": 1 + len(strips),
        "strips": [
            {"id": strip["id"], "state": strip["state"], "start": strip["start"], "count": strip["count"]}
            for strip in strips
        ],
        "rows": [
            {
                "state": state["id"],
                "row": state["row"],
                "frames": state["frames"],
                "duration_ms": state["duration_ms"],
                "derive_from": state.get("derive_from"),
            }
            for state in STATES
        ],
    }
    (run_dir / "pet_request.json").write_text(json.dumps(request, indent=2) + "\n", encoding="utf-8")
    (run_dir / "imagegen-jobs.json").write_text(
        json.dumps(
            {
                "schema_version": 3,
                "created_at": request["created_at"],
                "run_dir": str(run_dir),
                "jobs": jobs,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    ready = [job["id"] for job in jobs if job["depends_on"] == []]
    print(
        json.dumps(
            {
                "ok": True,
                "run_dir": str(run_dir),
                "ready_jobs": ready,
                "generation_images": 1 + len(strips),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
