#!/usr/bin/env python3
"""Shared contract, chroma, and shared-camera fitting for hatch-aibo."""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, replace
from typing import Iterable

from PIL import Image, ImageDraw

try:
    import numpy as np
except ImportError:  # pragma: no cover - optional speed path
    np = None

CELL_WIDTH = 192
CELL_HEIGHT = 208
COLUMNS = 8
V1_ROWS = 9
V2_ROWS = 11
STAGE_SCALE = 4
STAGE_WIDTH = CELL_WIDTH * STAGE_SCALE
STAGE_HEIGHT = CELL_HEIGHT * STAGE_SCALE
GROUND_FRAC = 0.86
SAFE_MARGIN_X = 48
SAFE_MARGIN_Y = 52
EDGE_MARGIN = 2
CHROMA_THRESHOLD = 96.0
STRIP_SLOT_WIDTH = 256
STRIP_GUTTER = 80
STRIP_HEIGHT = 320

CHROMA_KEY_CANDIDATES = [
    ("magenta", "#FF00FF"),
    ("cyan", "#00FFFF"),
    ("yellow", "#FFFF00"),
    ("blue", "#0000FF"),
    ("orange", "#FF7F00"),
    ("green", "#00FF00"),
]

STYLE_PRESETS = {
    "auto": (
        "Infer the most appropriate pet-safe style from the request and "
        "references, then keep that exact style on every frame."
    ),
    "pixel": (
        "Pixel-art-adjacent mascot: chunky silhouette, simple dark outline, "
        "limited palette, flat cel shading, stepped edges."
    ),
    "plush": "Soft plush-toy mascot with rounded stitched forms and readable toy proportions.",
    "clay": "Handmade clay mascot with rounded sculpted forms and clean edges.",
    "sticker": "Polished sticker mascot with bold shapes, crisp outline, and flat color.",
    "flat-vector": "Flat vector mascot with geometric forms, crisp color areas, and a clean outline.",
    "3d-toy": "Stylized 3D toy mascot with smooth rounded forms and simple materials.",
    "painterly": "Painterly mascot with simplified brush texture and edges clear enough to extract.",
}

STATES: list[dict[str, object]] = [
    {
        "id": "idle",
        "row": 0,
        "frames": 6,
        "duration_ms": 1100,
        "frame_durations": [150, 170, 200, 180, 160, 240],
        "vertical": "planted",
        "action": (
            "Calm idle loop: tiny breath and an optional blink. Feet stay planted. "
            "No walking, waving, jumping, or new props."
        ),
        "keys": [0, 2, 5],
        "phases": [
            "Neutral standing rest. Eyes open. Full body and every prop inside the safe box. Loop start.",
            "In-between toward the quiet variation. Feet locked to frame 00. Do not shift the hips.",
            "Quiet variation: a blink or a very small breath. Legs, feet, and prop layout locked to frame 00.",
            "In-between returning from the variation. Feet still locked. Props fully inside the safe box.",
            "Almost back to rest. Eyes opening if they were closed. Feet locked.",
            "Loop end: visually very close to frame 00 so the cycle does not pop.",
        ],
    },
    {
        "id": "running-right",
        "row": 1,
        "frames": 8,
        "duration_ms": 1060,
        "frame_durations": [170, 110, 130, 110, 170, 110, 130, 130],
        "vertical": "planted",
        "action": (
            "Side-view run traveling RIGHT. Legs must cross: right-foot-forward and "
            "left-foot-forward contacts both appear in the 8-frame loop."
        ),
        "keys": [0, 2, 4, 6],
        "phases": [
            "KEY contact A. Face and travel RIGHT. RIGHT foot planted in front (toward the right). LEFT foot behind, toe leaving the ground. Opposite of frame 04.",
            "In-between: LEFT leg swinging forward from behind. Do not keep the same leg in front as frame 00.",
            "KEY passing A. Face RIGHT. LEFT leg passing through the middle, crossing the RIGHT leg. Feet closer together than at contact.",
            "In-between into the opposite contact. LEFT foot reaching forward to plant. This is the crossover.",
            "KEY contact B / crossover. Face and travel RIGHT. LEFT foot planted in front. RIGHT foot behind. Front and back legs MUST be swapped vs frame 00.",
            "In-between: RIGHT leg swinging forward from behind.",
            "KEY passing B. Face RIGHT. RIGHT leg passing through the middle, crossing the LEFT leg.",
            "In-between back to contact A. RIGHT foot reaching forward so the loop can return to frame 00.",
        ],
    },
    {
        "id": "running-left",
        "row": 2,
        "frames": 8,
        "duration_ms": 1060,
        "frame_durations": [170, 110, 130, 110, 170, 110, 130, 130],
        "vertical": "planted",
        "action": "Mirror of running-right: face and travel LEFT. Same crossover cadence.",
        "keys": [],
        "derive_from": "running-right",
        "phases": [],
    },
    {
        "id": "waving",
        "row": 3,
        "frames": 4,
        "duration_ms": 700,
        "frame_durations": [140, 140, 140, 280],
        "vertical": "planted",
        "action": "Greeting wave using a paw, hand, wing, or limb only. No motion lines or sparkles.",
        "keys": [0, 1, 3],
        "phases": [
            "KEY rest: waving limb down or close to the body. Feet planted.",
            "KEY peak: waving limb raised. Clear silhouette, still inside the safe box.",
            "In-between lowering the wave toward rest.",
            "KEY return: nearly back to frame 00 so the loop closes.",
        ],
    },
    {
        "id": "jumping",
        "row": 4,
        "frames": 5,
        "duration_ms": 840,
        "frame_durations": [140, 140, 140, 140, 280],
        "vertical": "stage",
        "action": (
            "Jump through body height only: crouch, lift, peak, descent, land. "
            "Do not enlarge the character. No ground shadows or dust."
        ),
        "keys": [0, 2, 4],
        "phases": [
            "KEY crouch / anticipation. Feet on the ground line. Same scale as the base.",
            "In-between rising. Whole body higher than frame 00. Same scale, do not zoom in.",
            "KEY peak. Feet off the ground line. Body highest in the stage. Same scale as the base.",
            "In-between descending. Body lower than the peak, feet not yet planted.",
            "KEY land / settle. Feet back on the ground line. Same scale as the base.",
        ],
    },
    {
        "id": "failed",
        "row": 5,
        "frames": 8,
        "duration_ms": 1220,
        "frame_durations": [140, 140, 140, 140, 140, 140, 140, 240],
        "vertical": "planted",
        "action": "Blocked or failed reaction: slump, droop, sad or closed eyes. No floating X marks.",
        "keys": [0, 3, 7],
        "phases": [
            "KEY start: just reacting, still mostly upright.",
            "In-between sinking into the slump.",
            "In-between continuing the slump.",
            "KEY lowest: most slumped or sad. Attached tears/smoke only if they overlap the body.",
            "In-between holding the slump with a tiny shift.",
            "In-between still slumped.",
            "In-between toward the loop hold.",
            "KEY hold: still slumped, close to frame 03 so the loop reads as failure not idle.",
        ],
    },
    {
        "id": "waiting",
        "row": 6,
        "frames": 6,
        "duration_ms": 1010,
        "frame_durations": [150, 150, 150, 150, 150, 260],
        "vertical": "planted",
        "action": "Expectant asking pose: needs approval or input. Not idle, not review.",
        "keys": [0, 3, 5],
        "phases": [
            "KEY expectant rest: looking toward the viewer, waiting.",
            "In-between into a clearer ask (lean or head tilt).",
            "In-between continuing the ask.",
            "KEY peak ask: most expectant readable pose.",
            "In-between easing back.",
            "KEY loop end: close to frame 00, still waiting not idle.",
        ],
    },
    {
        "id": "running",
        "row": 7,
        "frames": 6,
        "duration_ms": 820,
        "frame_durations": [120, 120, 120, 120, 120, 220],
        "vertical": "planted",
        "action": (
            "Active task work: thinking, typing, scanning, or concentrating. "
            "NOT locomotion. No jogging, raised knees, or directional travel."
        ),
        "keys": [0, 2, 5],
        "phases": [
            "KEY focused work pose. Feet planted. Busy hands/paws or a thinking beat.",
            "In-between into a busier work beat.",
            "KEY busy work: a distinct working gesture, still not walking.",
            "In-between continuing the work beat.",
            "In-between easing back.",
            "KEY loop end: close to frame 00, still working.",
        ],
    },
    {
        "id": "review",
        "row": 8,
        "frames": 6,
        "duration_ms": 1030,
        "frame_durations": [150, 150, 150, 150, 150, 280],
        "vertical": "planted",
        "action": "Review completed output: lean, blink, narrowed eyes, or head tilt. No new props.",
        "keys": [0, 3, 5],
        "phases": [
            "KEY inspect: slight lean or narrowed eyes.",
            "In-between into a clearer inspect beat.",
            "In-between continuing the inspect.",
            "KEY peak inspect: blink or head tilt, still the same pet.",
            "In-between easing back.",
            "KEY loop end: close to frame 00.",
        ],
    },
]

LOOK_KEYS = [0, 2, 4, 6, 8, 10, 12, 14]
LOOK_COUNT = 16
LOOK_STEP_DEGREES = 22.5

LOOK_FACING = [
    "0° up: back view, top of head toward the top of the frame, facing away from camera",
    "22.5° up-right: three-quarter back, turning toward the right",
    "45° up-right: between back and right profile",
    "67.5° approaching right profile",
    "90° right: full right profile, face toward the right edge",
    "112.5° down-right: between right profile and front",
    "135° down-right three-quarter front",
    "157.5° approaching front",
    "180° down / front: full face toward camera",
    "202.5° down-left: between front and left profile",
    "225° down-left three-quarter front",
    "247.5° approaching left profile",
    "270° left: full left profile, face toward the left edge",
    "292.5° up-left: between left profile and back",
    "315° up-left three-quarter back",
    "337.5° approaching back / up",
]


def state_by_id(state_id: str) -> dict[str, object]:
    for state in STATES:
        if state["id"] == state_id:
            return state
    raise KeyError(state_id)


def iter_generation_strips(atlas_version: int) -> list[dict[str, object]]:
    """One generated image per strip. V1 ≈ 10 images, V2 ≈ 12."""
    strips: list[dict[str, object]] = []
    for state in STATES:
        if "derive_from" in state:
            continue
        state_id = str(state["id"])
        if state_id == "running-right":
            strips.append(
                {
                    "id": "running-right-a",
                    "state": state_id,
                    "start": 0,
                    "count": 4,
                    "depends_on": ["base"],
                }
            )
            strips.append(
                {
                    "id": "running-right-b",
                    "state": state_id,
                    "start": 4,
                    "count": 4,
                    "depends_on": ["base", "running-right-a"],
                    "reference_strip": "running-right-a",
                }
            )
            continue
        strips.append(
            {
                "id": state_id,
                "state": state_id,
                "start": 0,
                "count": int(state["frames"]),
                "depends_on": ["base"],
            }
        )
    if atlas_version >= 2:
        strips.append(
            {
                "id": "look-a",
                "state": "look",
                "start": 0,
                "count": 8,
                "depends_on": ["base"],
            }
        )
        strips.append(
            {
                "id": "look-b",
                "state": "look",
                "start": 8,
                "count": 8,
                "depends_on": ["base", "look-a"],
                "reference_strip": "look-a",
            }
        )
    return strips


def slugify(value: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9]+", "-", value)
    value = re.sub(r"-{2,}", "-", value)
    return value.strip("-")


def parse_hex_color(value: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        raise ValueError(f"invalid chroma key: {value}")
    return tuple(int(value[index : index + 2], 16) for index in (1, 3, 5))


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}"


def color_distance(left: tuple[int, int, int], right: tuple[int, int, int]) -> float:
    return math.sqrt(sum((left[index] - right[index]) ** 2 for index in range(3)))


def choose_chroma_key(reference_paths: Iterable, requested: str) -> dict[str, object]:
    if requested.lower() != "auto":
        rgb = parse_hex_color(requested)
        return {"hex": rgb_to_hex(rgb), "rgb": list(rgb), "name": "user-selected", "selection": "manual"}

    pixels: list[tuple[int, int, int]] = []
    for path in reference_paths:
        with Image.open(path) as opened:
            image = opened.convert("RGBA")
            image.thumbnail((96, 96), Image.Resampling.LANCZOS)
            data = image.tobytes()
            for index in range(0, len(data), 4):
                red, green, blue, alpha = data[index : index + 4]
                if alpha <= 16:
                    continue
                if red > 244 and green > 244 and blue > 244:
                    continue
                pixels.append((red, green, blue))
    if not pixels:
        rgb = parse_hex_color("#FF00FF")
        return {"hex": "#FF00FF", "rgb": list(rgb), "name": "magenta", "selection": "fallback"}

    scored: list[tuple[float, int, str, tuple[int, int, int]]] = []
    for preference_index, (name, hex_color) in enumerate(CHROMA_KEY_CANDIDATES):
        rgb = parse_hex_color(hex_color)
        distances = sorted(color_distance(rgb, pixel) for pixel in pixels)
        percentile_index = max(0, min(len(distances) - 1, int(len(distances) * 0.01)))
        scored.append((distances[percentile_index], -preference_index, name, rgb))
    _score, _preference, name, rgb = max(scored)
    return {"hex": rgb_to_hex(rgb), "rgb": list(rgb), "name": name, "selection": "auto"}


def remove_chroma(
    image: Image.Image,
    key: tuple[int, int, int],
    threshold: float = CHROMA_THRESHOLD,
) -> Image.Image:
    rgba = image.convert("RGBA")
    if np is not None:
        arr = np.array(rgba)
        rgb = arr[:, :, :3].astype(np.int32)
        dist = np.sqrt(((rgb - np.array(key, dtype=np.int32)) ** 2).sum(axis=2))
        hard = float(threshold)
        soft = hard * 1.85
        alpha = arr[:, :, 3].astype(np.float32)
        fade = np.clip((dist - hard) / max(1.0, soft - hard), 0.0, 1.0)
        alpha *= fade
        red = arr[:, :, 0].astype(np.int16)
        green = arr[:, :, 1].astype(np.int16)
        blue = arr[:, :, 2].astype(np.int16)
        limit = np.maximum(red, blue)
        fringe = (green > red + 18) & (green > blue + 18) & (green > 36) & (limit < 90)
        alpha = np.where(fringe, 0.0, alpha)
        excess = green - limit
        despill = excess > 6
        green = np.where(despill, limit + 6, green)
        arr[:, :, 0] = np.clip(red, 0, 255).astype(np.uint8)
        arr[:, :, 1] = np.clip(green, 0, 255).astype(np.uint8)
        arr[:, :, 2] = np.clip(blue, 0, 255).astype(np.uint8)
        arr[:, :, 3] = np.clip(alpha, 0, 255).astype(np.uint8)
        transparent = arr[:, :, 3] == 0
        arr[:, :, 0][transparent] = 0
        arr[:, :, 1][transparent] = 0
        arr[:, :, 2][transparent] = 0
        return Image.fromarray(arr, "RGBA")

    pixels = rgba.load()
    key_red, key_green, key_blue = key
    soft = threshold * 1.85
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, alpha = pixels[x, y]
            dist = color_distance((red, green, blue), key)
            if dist <= threshold:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            if dist < soft:
                alpha = int(alpha * (dist - threshold) / max(1.0, soft - threshold))
            limit = max(red, blue)
            if green > red + 18 and green > blue + 18 and green > 36 and limit < 90:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            if green > limit + 6:
                green = limit + 6
            pixels[x, y] = (red, green, blue, alpha)
    return rgba


def clear_transparent_rgb(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    if np is not None:
        arr = np.array(rgba)
        transparent = arr[:, :, 3] == 0
        arr[:, :, 0][transparent] = 0
        arr[:, :, 1][transparent] = 0
        arr[:, :, 2][transparent] = 0
        return Image.fromarray(arr, "RGBA")
    data = bytearray(rgba.tobytes())
    for index in range(0, len(data), 4):
        if data[index + 3] == 0:
            data[index] = 0
            data[index + 1] = 0
            data[index + 2] = 0
    return Image.frombytes("RGBA", rgba.size, bytes(data))


def alpha_count(image: Image.Image) -> int:
    alpha = image if image.mode == "L" else image.getchannel("A")
    return sum(alpha.histogram()[1:])


def edge_alpha_count(image: Image.Image, margin: int = EDGE_MARGIN) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    width, height = alpha.size
    top = alpha_count(alpha.crop((0, 0, width, margin)))
    bottom = alpha_count(alpha.crop((0, height - margin, width, height)))
    left = alpha_count(alpha.crop((0, 0, margin, height)))
    right = alpha_count(alpha.crop((width - margin, 0, width, height)))
    return left, right, top, bottom


@dataclass
class SpriteMeasure:
    width: int
    height: int
    bbox: tuple[int, int, int, int] | None
    body_cx: float
    foot_y: float
    bbox_width: int
    bbox_height: int
    opaque: int
    left_edge: int
    right_edge: int
    top_edge: int
    bottom_edge: int
    stage_lift: float = 0.0


def _median(values: list[float]) -> float:
    ordered = sorted(values)
    return ordered[len(ordered) // 2]


def planted_foot_y(image: Image.Image, bbox: tuple[int, int, int, int], body_cx: float) -> float:
    """Lowest opaque row under the torso, ignoring flared hair/props at the sides."""
    x0, y0, x1, y1 = bbox
    band_w = max(8, int((x1 - x0) * 0.45))
    center = int(body_cx)
    left = max(x0, center - band_w // 2)
    right = min(x1, max(left + 1, center + band_w // 2))
    band = image.crop((left, y0, right, y1)).getchannel("A")
    min_opaque = max(2, int(band.width * 0.08))
    pixels = band.load()
    for y in range(band.height - 1, -1, -1):
        count = 0
        for x in range(band.width):
            if pixels[x, y] > 16:
                count += 1
                if count >= min_opaque:
                    return float(y0 + y + 1)
    return float(y1)


def body_center_x(image: Image.Image, bbox: tuple[int, int, int, int]) -> float:
    x0, y0, x1, y1 = bbox
    band_top = y0 + int((y1 - y0) * 0.35)
    band_bottom = max(band_top + 1, y0 + int((y1 - y0) * 0.75))
    band = image.crop((x0, band_top, x1, band_bottom)).getchannel("A")
    total = 0
    weighted = 0.0
    pixels = band.load()
    for y in range(band.height):
        for x in range(band.width):
            value = pixels[x, y]
            if value <= 16:
                continue
            total += value
            weighted += (x0 + x + 0.5) * value
    if total == 0:
        return (x0 + x1) / 2
    return weighted / total


def measure_sprite(image: Image.Image) -> SpriteMeasure:
    rgba = image.convert("RGBA")
    bbox = rgba.getbbox()
    left, right, top, bottom = edge_alpha_count(rgba)
    if bbox is None:
        return SpriteMeasure(
            width=rgba.width,
            height=rgba.height,
            bbox=None,
            body_cx=rgba.width / 2,
            foot_y=rgba.height * GROUND_FRAC,
            bbox_width=0,
            bbox_height=0,
            opaque=0,
            left_edge=left,
            right_edge=right,
            top_edge=top,
            bottom_edge=bottom,
            stage_lift=0.0,
        )
    x0, y0, x1, y1 = bbox
    center_x = body_center_x(rgba, bbox)
    return SpriteMeasure(
        width=rgba.width,
        height=rgba.height,
        bbox=bbox,
        body_cx=center_x,
        foot_y=planted_foot_y(rgba, bbox, center_x),
        bbox_width=x1 - x0,
        bbox_height=y1 - y0,
        opaque=alpha_count(rgba),
        left_edge=left,
        right_edge=right,
        top_edge=top,
        bottom_edge=bottom,
        stage_lift=0.0,
    )


def wrap_suspected(measure: SpriteMeasure, min_pixels: int = 12) -> bool:
    if measure.bbox is None:
        return False
    return measure.left_edge >= min_pixels and measure.right_edge >= min_pixels


@dataclass
class SharedCamera:
    scale: float
    baseline: int
    padding: int
    target_identity: float
    top_pad: int
    bottom_pad: int
    ground_frac: float = GROUND_FRAC


def identity_height(measure: SpriteMeasure) -> float:
    if measure.bbox is None:
        return 1.0
    return max(1.0, measure.foot_y - measure.bbox[1])


def below_plant(measure: SpriteMeasure) -> float:
    if measure.bbox is None:
        return 1.0
    return max(1.0, float(measure.bbox[3] - measure.foot_y))


def compute_shared_camera(
    measurements: list[SpriteMeasure],
    padding: int = 10,
    extra_headrooms: list[float] | None = None,
) -> SharedCamera:
    top_pad = 8
    bottom_pad = 22
    baseline = CELL_HEIGHT - bottom_pad
    target = float(baseline - top_pad)
    idents = [
        identity_height(measure)
        for measure in measurements
        if measure.bbox is not None and measure.bbox_width >= 8
    ]
    scale = target / _median(idents) if idents else 1.0
    for span in extra_headrooms or []:
        if span > 1:
            scale = min(scale, (baseline - top_pad) / span)
    if not math.isfinite(scale) or scale <= 0:
        scale = 1.0
    return SharedCamera(
        scale=scale,
        baseline=baseline,
        padding=padding,
        target_identity=target,
        top_pad=top_pad,
        bottom_pad=bottom_pad,
    )


def scale_for_frame(measure: SpriteMeasure, camera: SharedCamera, match_identity: bool) -> float:
    if measure.bbox is None:
        return camera.scale
    scale = camera.target_identity / identity_height(measure) if match_identity else camera.scale
    scale = min(scale, camera.bottom_pad / below_plant(measure))
    if not match_identity:
        x0, _y0, x1, _y1 = measure.bbox
        half_w = CELL_WIDTH / 2 - camera.padding
        left_extent = max(1.0, measure.body_cx - x0)
        right_extent = max(1.0, x1 - measure.body_cx)
        scale = min(scale, half_w / left_extent, half_w / right_extent)
    if measure.stage_lift > 0:
        span = (measure.foot_y - measure.bbox[1]) + measure.stage_lift
        if span > 1:
            scale = min(scale, (camera.baseline - camera.top_pad) / span)
    if not math.isfinite(scale) or scale <= 0:
        return camera.scale
    return scale


LOCK_PLANT_STATES = {
    "idle",
    "waving",
    "waiting",
    "review",
    "failed",
    "look",
    "running",
}


def stabilize_state_measures(state_id: str, measures: list[SpriteMeasure]) -> list[SpriteMeasure]:
    """Keep standing cycles on one planted line so a tapping toe doesn't lift the body."""
    if state_id == "jumping":
        foots = [measure.foot_y for measure in measures if measure.bbox is not None]
        if not foots:
            return measures
        plant = max(foots)
        return [
            replace(measure, stage_lift=max(0.0, plant - measure.foot_y))
            for measure in measures
        ]
    if state_id in {"running-right", "running-left"}:
        # Plant on the lowest foot so a trailing toe is not below the cell.
        return [
            replace(measure, foot_y=float(measure.bbox[3])) if measure.bbox is not None else measure
            for measure in measures
        ]
    if state_id not in LOCK_PLANT_STATES:
        return measures
    foots = [measure.foot_y for measure in measures if measure.bbox is not None]
    if not foots:
        return measures
    plant = _median(foots)
    return [replace(measure, foot_y=plant) for measure in measures]


def _composite_at(target: Image.Image, source: Image.Image, dest_x: int, dest_y: int) -> None:
    src_x = max(0, -dest_x)
    src_y = max(0, -dest_y)
    dst_x = max(0, dest_x)
    dst_y = max(0, dest_y)
    width = min(source.width - src_x, target.width - dst_x)
    height = min(source.height - src_y, target.height - dst_y)
    if width <= 0 or height <= 0:
        return
    piece = source.crop((src_x, src_y, src_x + width, src_y + height))
    target.alpha_composite(piece, (dst_x, dst_y))


def fit_to_camera(
    image: Image.Image,
    measure: SpriteMeasure,
    camera: SharedCamera,
    vertical: str,
    scale: float | None = None,
) -> Image.Image:
    target = Image.new("RGBA", (CELL_WIDTH, CELL_HEIGHT), (0, 0, 0, 0))
    if measure.bbox is None:
        return target
    frame_scale = camera.scale if scale is None else scale
    x0, y0, x1, y1 = measure.bbox
    crop = image.crop((x0, y0, x1, y1))
    scaled_w = max(1, round(crop.width * frame_scale))
    scaled_h = max(1, round(crop.height * frame_scale))
    scaled = crop.resize((scaled_w, scaled_h), Image.Resampling.LANCZOS)
    body_cx = (measure.body_cx - x0) * frame_scale
    dest_x = round(CELL_WIDTH / 2 - body_cx)
    dest_y = round(camera.baseline - (measure.foot_y - y0) * frame_scale)
    if vertical == "stage":
        dest_y = round(
            camera.baseline
            - (measure.foot_y - y0) * frame_scale
            - measure.stage_lift * frame_scale
        )
    _composite_at(target, scaled, dest_x, dest_y)
    return target


def opaque_column_counts(image: Image.Image, alpha_threshold: int = 16) -> list[int]:
    alpha = image.getchannel("A")
    if np is not None:
        return [int(value) for value in (np.array(alpha) > alpha_threshold).sum(axis=0)]
    pixels = alpha.load()
    counts = [0] * alpha.width
    for x in range(alpha.width):
        total = 0
        for y in range(alpha.height):
            if pixels[x, y] > alpha_threshold:
                total += 1
        counts[x] = total
    return counts


def occupied_column_runs(counts: list[int], min_opaque: int) -> list[tuple[int, int]]:
    runs: list[tuple[int, int]] = []
    start: int | None = None
    for index, count in enumerate(counts):
        if count >= min_opaque:
            if start is None:
                start = index
        elif start is not None:
            runs.append((start, index))
            start = None
    if start is not None:
        runs.append((start, len(counts)))
    return runs


def merge_runs(runs: list[tuple[int, int]], target: int) -> list[tuple[int, int]]:
    merged = list(runs)
    while len(merged) > target:
        gap_index = min(
            range(len(merged) - 1),
            key=lambda index: merged[index + 1][0] - merged[index][1],
        )
        left = merged[gap_index]
        right = merged[gap_index + 1]
        merged[gap_index] = (left[0], right[1])
        del merged[gap_index + 1]
    return merged


def split_strip(image: Image.Image, frame_count: int, padding: int = 8) -> tuple[list[Image.Image], str]:
    """Split a guttered strip by 1D occupancy, never 2D connected components."""
    counts = opaque_column_counts(image)
    min_opaque = max(8, int(image.height * 0.02))
    runs = occupied_column_runs(counts, min_opaque)
    if len(runs) < frame_count:
        slot_width = image.width / frame_count
        crops = [
            image.crop(
                (round(index * slot_width), 0, round((index + 1) * slot_width), image.height)
            )
            for index in range(frame_count)
        ]
        return crops, "equal-slots"
    if len(runs) > frame_count:
        runs = merge_runs(runs, frame_count)
    crops: list[Image.Image] = []
    for index, (left, right) in enumerate(runs):
        prev_end = runs[index - 1][1] if index else 0
        next_start = runs[index + 1][0] if index + 1 < len(runs) else image.width
        pad_left = min(padding, max(0, (left - prev_end) // 2), left)
        pad_right = min(padding, max(0, (next_start - right) // 2), image.width - right)
        crops.append(image.crop((left - pad_left, 0, right + pad_right, image.height)))
    return crops, "gutters"


def create_strip_guide(path, frames: int, chroma_hex: str) -> None:
    width = frames * STRIP_SLOT_WIDTH + max(0, frames - 1) * STRIP_GUTTER
    image = Image.new("RGB", (width, STRIP_HEIGHT), chroma_hex)
    draw = ImageDraw.Draw(image)
    ground_y = round(STRIP_HEIGHT * GROUND_FRAC)
    for index in range(frames):
        left = index * (STRIP_SLOT_WIDTH + STRIP_GUTTER)
        right = left + STRIP_SLOT_WIDTH - 1
        safe = (left + 18, 16, right - 18, STRIP_HEIGHT - 17)
        draw.rectangle((left, 0, right, STRIP_HEIGHT - 1), outline="#111111", width=2)
        draw.rectangle(safe, outline="#2f80ed", width=2)
        for x in range(safe[0], safe[2], 16):
            draw.line((x, ground_y, min(x + 8, safe[2]), ground_y), fill="#111111")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def create_stage_guide(path, chroma_hex: str) -> None:
    image = Image.new("RGB", (STAGE_WIDTH, STAGE_HEIGHT), chroma_hex)
    draw = ImageDraw.Draw(image)
    safe = (
        SAFE_MARGIN_X,
        SAFE_MARGIN_Y,
        STAGE_WIDTH - 1 - SAFE_MARGIN_X,
        STAGE_HEIGHT - 1 - SAFE_MARGIN_Y,
    )
    draw.rectangle(safe, outline="#111111", width=3)
    ground_y = round(STAGE_HEIGHT * GROUND_FRAC)
    for x in range(SAFE_MARGIN_X, STAGE_WIDTH - SAFE_MARGIN_X, 16):
        draw.line((x, ground_y, min(x + 8, STAGE_WIDTH - SAFE_MARGIN_X), ground_y), fill="#111111")
    center_x = STAGE_WIDTH // 2
    for y in range(SAFE_MARGIN_Y, STAGE_HEIGHT - SAFE_MARGIN_Y, 16):
        draw.line((center_x, y, center_x, min(y + 8, STAGE_HEIGHT - SAFE_MARGIN_Y)), fill="#4a4a4a")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path)


def look_inbetween_depends(index: int) -> list[int]:
    if index in LOOK_KEYS:
        return []
    left = (index - 1) % LOOK_COUNT
    right = (index + 1) % LOOK_COUNT
    return [left, right]


def lower_mask(image: Image.Image) -> Image.Image:
    height = image.height
    top = int(height * 0.70)
    return image.crop((0, top, image.width, height)).getchannel("A").point(
        lambda value: 255 if value > 16 else 0
    )


def mask_iou(left: Image.Image, right: Image.Image) -> float:
    if left.size != right.size:
        right = right.resize(left.size, Image.Resampling.NEAREST)
    if np is not None:
        a = np.array(left) > 0
        b = np.array(right) > 0
        intersection = np.logical_and(a, b).sum()
        union = np.logical_or(a, b).sum()
        return float(intersection / union) if union else 1.0
    intersection = 0
    union = 0
    la = left.load()
    ra = right.load()
    for y in range(left.height):
        for x in range(left.width):
            lv = la[x, y] > 0
            rv = ra[x, y] > 0
            if lv or rv:
                union += 1
            if lv and rv:
                intersection += 1
    return intersection / union if union else 1.0
