#!/usr/bin/env python3
"""Fit decoded frames with a shared camera, then write clips, atlas, QA, and packages."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

from hatch_lib import (
    CELL_HEIGHT,
    CELL_WIDTH,
    COLUMNS,
    STATES,
    V1_ROWS,
    V2_ROWS,
    SharedCamera,
    SpriteMeasure,
    clear_transparent_rgb,
    compute_shared_camera,
    edge_alpha_count,
    fit_to_camera,
    identity_height,
    iter_generation_strips,
    lower_mask,
    mask_iou,
    measure_sprite,
    parse_hex_color,
    remove_chroma,
    scale_for_frame,
    split_strip,
    stabilize_state_measures,
    state_by_id,
    wrap_suspected,
    below_plant,
)


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, data: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def chroma_tuple(request: dict) -> tuple[int, int, int]:
    chroma = request["chroma_key"]
    if isinstance(chroma.get("rgb"), list) and len(chroma["rgb"]) == 3:
        return tuple(int(value) for value in chroma["rgb"])  # type: ignore[return-value]
    return parse_hex_color(str(chroma["hex"]))


def load_rgba(path: Path) -> Image.Image:
    with Image.open(path) as opened:
        return opened.convert("RGBA")


def decoded_strip_path(run_dir: Path, strip_id: str) -> Path:
    return run_dir / "decoded" / f"{strip_id}.png"


def collect_source_images(run_dir: Path, atlas_version: int) -> dict[str, list[Path]]:
    """Load generated strips; assemble splits them later. Paths are strip files, not frames."""
    sources: dict[str, list[Path]] = {}
    base = run_dir / "decoded" / "base.png"
    if not base.is_file():
        raise SystemExit(f"missing base image: {base}")
    sources["base"] = [base]
    missing: list[str] = []
    for strip in iter_generation_strips(atlas_version):
        path = decoded_strip_path(run_dir, str(strip["id"]))
        if not path.is_file():
            missing.append(str(path))
            continue
        sources.setdefault(str(strip["id"]), []).append(path)
    if missing:
        raise SystemExit("missing generated strips:\n" + "\n".join(missing))
    return sources


def fitted_frame_path(run_dir: Path, state_id: str, index: int) -> Path:
    return run_dir / "frames" / state_id / f"{index:02d}.png"


def inspect_source(path: Path, measure: SpriteMeasure) -> list[str]:
    errors: list[str] = []
    if measure.opaque < 400:
        errors.append(f"{path} is empty or too sparse ({measure.opaque} opaque pixels)")
    return errors


def fit_all(
    run_dir: Path,
    atlas_version: int,
    chroma: tuple[int, int, int],
    threshold: float,
) -> tuple[SharedCamera, dict[str, list[Image.Image]], list[str], list[str], list[dict]]:
    errors: list[str] = []
    warnings: list[str] = []
    source_reviews: list[dict] = []
    grouped: dict[str, list[Image.Image]] = {"base": []}
    measures_by_state: dict[str, list[SpriteMeasure]] = {"base": []}

    base_path = run_dir / "decoded" / "base.png"
    base_image = remove_chroma(load_rgba(base_path), chroma, threshold)
    base_measure = measure_sprite(base_image)
    grouped["base"] = [base_image]
    measures_by_state["base"] = [base_measure]
    source_reviews.append(
        {
            "path": str(base_path),
            "state": "base",
            "split": "single",
            "opaque": base_measure.opaque,
            "errors": inspect_source(base_path, base_measure),
        }
    )
    errors.extend(inspect_source(base_path, base_measure))

    for strip in iter_generation_strips(atlas_version):
        strip_id = str(strip["id"])
        state_id = str(strip["state"])
        path = decoded_strip_path(run_dir, strip_id)
        strip_image = remove_chroma(load_rgba(path), chroma, threshold)
        crops, method = split_strip(strip_image, int(strip["count"]))
        if method == "equal-slots":
            warnings.append(
                f"{strip_id} had no clear gaps between poses; fell back to equal-width slots"
            )
        grouped.setdefault(state_id, [])
        measures_by_state.setdefault(state_id, [])
        for index, crop in enumerate(crops):
            measure = measure_sprite(crop)
            frame_errors = inspect_source(path, measure)
            wrapped = wrap_suspected(measure)
            # Tight gutter crops often touch both edges; that is not atlas wrap.
            if wrapped and method == "equal-slots":
                frame_errors.append(
                    f"{strip_id} slot {index:02d} has opaque pixels on both left and right edges"
                )
            elif wrapped:
                warnings.append(
                    f"{strip_id} slot {index:02d} fills its gutter crop; check hair/props"
                )
            errors.extend(frame_errors)
            source_reviews.append(
                {
                    "path": str(path),
                    "state": state_id,
                    "strip": strip_id,
                    "slot": index,
                    "split": method,
                    "opaque": measure.opaque,
                    "errors": frame_errors,
                }
            )
            grouped[state_id].append(crop)
            measures_by_state[state_id].append(measure)

    standing = [
        measure
        for state_id in ("idle", "waving", "review", "waiting")
        for measure in measures_by_state.get(state_id, [])
        if measure.opaque >= 400 and measure.bbox is not None
    ]
    jump_spans: list[float] = []
    jump_measures = measures_by_state.get("jumping", [])
    if jump_measures:
        planted_jump = stabilize_state_measures("jumping", jump_measures)
        for measure in planted_jump:
            if measure.bbox is None:
                continue
            jump_spans.append((measure.foot_y - measure.bbox[1]) + measure.stage_lift)
    camera = compute_shared_camera(standing, extra_headrooms=jump_spans)
    # Per-frame identity match keeps standing rows the same height. Crouch / run /
    # jump must share one scale for the whole state, or a squat looks like a zoom-in.
    identity_states = {
        "idle",
        "waving",
        "waiting",
        "review",
        "look",
        "running",
    }
    # One scale for the whole row: size from the tallest frame (usually upright),
    # so crouch shortens instead of zooming.
    shared_scale_states = {"failed", "running-right", "jumping"}
    fitted: dict[str, list[Image.Image]] = {}
    for state_id, images in grouped.items():
        if state_id == "base":
            vertical = "planted"
        elif state_id == "look":
            vertical = "planted"
        else:
            vertical = str(state_by_id(state_id)["vertical"])
        planted = stabilize_state_measures(state_id, measures_by_state[state_id])
        if state_id in shared_scale_states:
            tallest = max(
                (identity_height(measure) for measure in planted if measure.bbox is not None),
                default=1.0,
            )
            frame_scale = camera.target_identity / tallest if tallest > 1 else camera.scale
            for measure in planted:
                if measure.bbox is None:
                    continue
                frame_scale = min(frame_scale, camera.bottom_pad / below_plant(measure))
                if measure.stage_lift > 0:
                    span = (measure.foot_y - measure.bbox[1]) + measure.stage_lift
                    if span > 1:
                        frame_scale = min(
                            frame_scale, (camera.baseline - camera.top_pad) / span
                        )
            fitted[state_id] = [
                fit_to_camera(image, measure, camera, vertical, frame_scale)
                for image, measure in zip(images, planted)
            ]
        else:
            fitted[state_id] = [
                fit_to_camera(
                    image,
                    measure,
                    camera,
                    vertical,
                    scale_for_frame(measure, camera, state_id in identity_states),
                )
                for image, measure in zip(images, planted)
            ]
    frames_root = run_dir / "frames"
    if frames_root.exists():
        shutil.rmtree(frames_root)
    for state_id, images in fitted.items():
        if state_id == "base":
            continue
        for index, image in enumerate(images):
            output = fitted_frame_path(run_dir, state_id, index)
            output.parent.mkdir(parents=True, exist_ok=True)
            clear_transparent_rgb(image).save(output)
    return camera, fitted, errors, warnings, source_reviews


def derive_running_left(run_dir: Path, fitted: dict[str, list[Image.Image]]) -> None:
    right = fitted.get("running-right")
    if not right:
        raise SystemExit("running-right frames are required before mirroring running-left")
    mirrored = [ImageOps.mirror(frame) for frame in right]
    fitted["running-left"] = mirrored
    for index, image in enumerate(mirrored):
        output = fitted_frame_path(run_dir, "running-left", index)
        output.parent.mkdir(parents=True, exist_ok=True)
        clear_transparent_rgb(image).save(output)


def inspect_fitted(fitted: dict[str, list[Image.Image]]) -> tuple[list[str], list[str], list[dict]]:
    errors: list[str] = []
    warnings: list[str] = []
    rows: list[dict] = []
    for state_id, images in fitted.items():
        if state_id == "base":
            continue
        row_errors: list[str] = []
        row_warnings: list[str] = []
        for index, image in enumerate(images):
            measure = measure_sprite(image)
            left, right, top, bottom = edge_alpha_count(image)
            if measure.opaque < 400:
                row_errors.append(f"{state_id} {index:02d} is empty or too sparse")
            if measure.bbox is not None and measure.bbox[3] > CELL_HEIGHT:
                row_errors.append(
                    f"{state_id} {index:02d} overflows the cell bottom (bbox y1={measure.bbox[3]})"
                )
            elif bottom > 24:
                row_errors.append(
                    f"{state_id} {index:02d} has opaque pixels on the cell bottom (B{bottom})"
                )
            if wrap_suspected(measure, min_pixels=24):
                row_warnings.append(
                    f"{state_id} {index:02d} is tight against both cell edges "
                    "(prop may be clipped)"
                )
            if left + right + top > 80:
                row_warnings.append(
                    f"{state_id} {index:02d} is tight against the cell edge "
                    f"(L{left} R{right} T{top} B{bottom})"
                )
        if state_id in {"running-right", "running-left"} and len(images) >= 5:
            iou = mask_iou(lower_mask(images[0]), lower_mask(images[4]))
            if iou > 0.82:
                row_errors.append(
                    f"{state_id} frames 00 and 04 look too similar in the legs (iou={iou:.2f}); "
                    "crossover step is missing"
                )
            elif iou > 0.55:
                row_warnings.append(
                    f"{state_id} frames 00 and 04 leg iou={iou:.2f}; confirm the feet actually swap"
                )
        errors.extend(row_errors)
        warnings.extend(row_warnings)
        rows.append(
            {
                "state": state_id,
                "frames": len(images),
                "ok": not row_errors,
                "errors": row_errors,
                "warnings": row_warnings,
            }
        )
    standing_heights: list[float] = []
    for state_id in ("idle", "waving", "waiting", "review", "look", "running"):
        frames = fitted.get(state_id) or []
        heights = [
            identity_height(measure_sprite(frame))
            for frame in frames
            if measure_sprite(frame).bbox is not None
        ]
        if heights:
            standing_heights.append(sorted(heights)[len(heights) // 2])
    if standing_heights and max(standing_heights) / min(standing_heights) > 1.14:
        errors.append(
            "standing states differ in fitted height "
            f"(min={min(standing_heights):.0f} max={max(standing_heights):.0f}); "
            "shared camera failed to normalize"
        )
    return errors, warnings, rows


def compose_strip(frames: list[Image.Image]) -> Image.Image:
    strip = Image.new("RGBA", (CELL_WIDTH * len(frames), CELL_HEIGHT), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        strip.alpha_composite(clear_transparent_rgb(frame), (index * CELL_WIDTH, 0))
    return strip


def write_clips(run_dir: Path, fitted: dict[str, list[Image.Image]], atlas_version: int) -> dict:
    clips_dir = run_dir / "final" / "clips"
    if clips_dir.exists():
        shutil.rmtree(clips_dir)
    clips_dir.mkdir(parents=True, exist_ok=True)
    clips: dict[str, dict[str, object]] = {}
    for state in STATES:
        state_id = str(state["id"])
        frames = fitted[state_id]
        path = clips_dir / f"{state_id}.png"
        compose_strip(frames).save(path)
        clips[state_id] = {
            "file": f"clips/{state_id}.png",
            "frames": len(frames),
            "durationMilliseconds": state["duration_ms"],
        }
    look: list[dict[str, object]] = []
    if atlas_version >= 2:
        for index, frame in enumerate(fitted["look"]):
            relative = f"clips/look-{index:02d}.png"
            clear_transparent_rgb(frame).save(run_dir / "final" / relative)
            look.append({"index": index, "file": relative})
    manifest = {
        "format": "aibo",
        "formatVersion": 1,
        "sliceVersion": 1,
        "extends": "petdex-v2" if atlas_version >= 2 else "petdex-v1",
        "cellWidth": CELL_WIDTH,
        "cellHeight": CELL_HEIGHT,
        "clips": clips,
        "look": look,
    }
    write_json(run_dir / "final" / "aibo.json", manifest)
    return manifest


def write_atlas(run_dir: Path, fitted: dict[str, list[Image.Image]], atlas_version: int) -> Path:
    rows = V2_ROWS if atlas_version >= 2 else V1_ROWS
    atlas = Image.new("RGBA", (COLUMNS * CELL_WIDTH, rows * CELL_HEIGHT), (0, 0, 0, 0))
    for state in STATES:
        row = int(state["row"])
        for column, frame in enumerate(fitted[str(state["id"])]):
            atlas.alpha_composite(clear_transparent_rgb(frame), (column * CELL_WIDTH, row * CELL_HEIGHT))
    if atlas_version >= 2:
        for index, frame in enumerate(fitted["look"]):
            row = 9 + index // 8
            column = index % 8
            atlas.alpha_composite(
                clear_transparent_rgb(frame),
                (column * CELL_WIDTH, row * CELL_HEIGHT),
            )
    png_path = run_dir / "final" / "spritesheet.png"
    webp_path = run_dir / "final" / "spritesheet.webp"
    atlas = clear_transparent_rgb(atlas)
    atlas.save(png_path)
    atlas.save(webp_path, format="WEBP", lossless=True, quality=100, method=6, exact=True)
    return webp_path


def checker(size: tuple[int, int], square: int = 12) -> Image.Image:
    image = Image.new("RGB", size, "#ffffff")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], square):
        for x in range(0, size[0], square):
            if (x // square + y // square) % 2:
                draw.rectangle((x, y, x + square - 1, y + square - 1), fill="#e8e8e8")
    return image


def write_contact_sheet(run_dir: Path, fitted: dict[str, list[Image.Image]], atlas_version: int) -> None:
    scale = 0.5
    cell_w = max(1, round(CELL_WIDTH * scale))
    cell_h = max(1, round(CELL_HEIGHT * scale))
    label_h = 22
    bands: list[tuple[str, list[Image.Image]]] = [
        (f"{index}: {state['id']}", fitted[str(state["id"])]) for index, state in enumerate(STATES)
    ]
    if atlas_version >= 2:
        bands.append(("9: look 00-07", fitted["look"][:8]))
        bands.append(("10: look 08-15", fitted["look"][8:]))
    width = COLUMNS * cell_w
    height = len(bands) * (cell_h + label_h)
    sheet = Image.new("RGB", (width, height), "#f7f7f7")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for row_index, (label, frames) in enumerate(bands):
        y = row_index * (cell_h + label_h)
        draw.rectangle((0, y, width, y + label_h - 1), fill="#111111")
        draw.text((6, y + 5), f"row {label}", fill="#ffffff", font=font)
        draw.text((width - 92, y + 5), f"{len(frames)} frames", fill="#ffffff", font=font)
        for column, frame in enumerate(frames[:COLUMNS]):
            preview = frame.resize((cell_w, cell_h), Image.Resampling.LANCZOS)
            bg = checker((cell_w, cell_h))
            bg.paste(preview, (0, 0), preview)
            sheet.paste(bg, (column * cell_w, y + label_h))
    output = run_dir / "qa" / "contact-sheet.png"
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def write_previews(run_dir: Path, fitted: dict[str, list[Image.Image]]) -> None:
    preview_dir = run_dir / "qa" / "previews"
    preview_dir.mkdir(parents=True, exist_ok=True)
    for state in STATES:
        state_id = str(state["id"])
        frames = [clear_transparent_rgb(frame) for frame in fitted[state_id]]
        durations = list(state["frame_durations"])  # type: ignore[arg-type]
        frames[0].save(
            preview_dir / f"{state_id}.gif",
            save_all=True,
            append_images=frames[1:],
            duration=durations,
            loop=0,
            disposal=2,
            optimize=False,
        )


def write_pet_json(run_dir: Path, request: dict, atlas_version: int) -> None:
    write_json(
        run_dir / "final" / "pet.json",
        {
            "id": request["pet_id"],
            "displayName": request["display_name"],
            "description": request["description"],
            "spritesheetPath": "spritesheet.webp",
            "spriteVersionNumber": atlas_version,
        },
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--key-threshold", type=float, default=96.0)
    parser.add_argument("--allow-errors", action="store_true")
    args = parser.parse_args()

    run_dir = Path(args.run_dir).expanduser().resolve()
    request = load_json(run_dir / "pet_request.json")
    atlas_version = int(request.get("atlas_version", 2))
    chroma = chroma_tuple(request)
    collect_source_images(run_dir, atlas_version)
    camera, fitted, source_errors, split_warnings, source_reviews = fit_all(
        run_dir, atlas_version, chroma, args.key_threshold
    )
    derive_running_left(run_dir, fitted)
    fit_errors, fit_warnings, rows = inspect_fitted(fitted)
    errors = source_errors + fit_errors
    warnings = split_warnings + fit_warnings

    write_clips(run_dir, fitted, atlas_version)
    webp = write_atlas(run_dir, fitted, atlas_version)
    write_contact_sheet(run_dir, fitted, atlas_version)
    write_previews(run_dir, fitted)
    write_pet_json(run_dir, request, atlas_version)

    review = {
        "ok": not errors,
        "camera": {
            "scale": camera.scale,
            "baseline": camera.baseline,
            "padding": camera.padding,
            "target_identity": camera.target_identity,
            "bottom_pad": camera.bottom_pad,
        },
        "errors": errors,
        "warnings": warnings,
        "rows": rows,
        "sources": source_reviews,
    }
    write_json(run_dir / "qa" / "review.json", review)
    write_json(
        run_dir / "qa" / "run-summary.json",
        {
            "ok": review["ok"],
            "run_dir": str(run_dir),
            "package": str(run_dir / "final"),
            "aibo_json": str(run_dir / "final" / "aibo.json"),
            "pet_json": str(run_dir / "final" / "pet.json"),
            "spritesheet": str(webp),
            "contact_sheet": str(run_dir / "qa" / "contact-sheet.png"),
            "review": str(run_dir / "qa" / "review.json"),
        },
    )
    print(json.dumps({k: review[k] for k in ("ok", "errors", "warnings", "camera")}, indent=2))
    if errors and not args.allow_errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
