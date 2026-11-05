"""Convert Kenney GLB models to USDZ for the claude-town app.

Run from the repository root:

    blender -b --python tools/convert-assets.py

Characters: Blender's USD export writes only the active animation, so this
script lays the clips listed in CLIPS end to end on one NLA track and exports
the whole timeline. It writes assets/models/clips.json with each clip's start
and end time in seconds, which the app uses to cut the timeline into clips.

Furniture: exported as static USDZ files.
"""

import json
import os
import sys

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC_CHARACTERS = os.path.join(ROOT, "assets", "kenney", "mini-characters")
SRC_FURNITURE = os.path.join(ROOT, "assets", "kenney", "furniture-kit")
OUT = os.path.join(ROOT, "assets", "models")

# Clips used by the scenes (see docs/roles.md, "Animations").
CLIPS = [
    "static",
    "idle",
    "walk",
    "sprint",
    "sit",
    "crouch",
    "interact-right",
    "interact-left",
    "holding-right",
    "holding-both",
    "pick-up",
    "emote-yes",
    "emote-no",
]

# Frames left empty between clips, so a clip never blends into the next one.
GAP = 2


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def find_armature():
    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if len(arms) != 1:
        raise RuntimeError(f"expected one armature, found {len(arms)}")
    return arms[0]


def convert_character(path, out_path):
    reset()
    bpy.ops.import_scene.gltf(filepath=path)
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    arm = find_armature()
    if arm.animation_data is None:
        arm.animation_data_create()
    ad = arm.animation_data

    actions = {a.name: a for a in bpy.data.actions}
    missing = [c for c in CLIPS if c not in actions]
    if missing:
        raise RuntimeError(f"{os.path.basename(path)}: missing clips {missing}")

    # Remove whatever the importer set up, then build one track.
    ad.action = None
    for t in list(ad.nla_tracks):
        ad.nla_tracks.remove(t)
    track = ad.nla_tracks.new()
    track.name = "clips"

    ranges = {}
    frame = 1
    for name in CLIPS:
        action = actions[name]
        start, end = action.frame_range
        length = max(1, int(round(end - start)))
        strip = track.strips.new(name, frame, action)
        # Blender 4.4+ uses slotted actions; bind the strip to the action's
        # first slot when the API has slots.
        if hasattr(strip, "action_slot") and getattr(action, "slots", None):
            strip.action_slot = action.slots[0]
        strip.action_frame_start = start
        strip.action_frame_end = start + length
        strip.frame_end = frame + length
        ranges[name] = {
            "start": round((frame - 1) / fps, 4),
            "end": round((frame - 1 + length) / fps, 4),
        }
        frame += length + GAP

    scene.frame_start = 1
    scene.frame_end = frame
    bpy.ops.wm.usd_export(
        filepath=out_path,
        export_animation=True,
        selected_objects_only=False,
    )
    return {"fps": fps, "clips": ranges}


def convert_static(path, out_path):
    reset()
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.ops.wm.usd_export(filepath=out_path, export_animation=False)


def main():
    os.makedirs(os.path.join(OUT, "characters"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "furniture"), exist_ok=True)

    clips = {}
    for f in sorted(os.listdir(SRC_CHARACTERS)):
        if not f.endswith(".glb"):
            continue
        name = f[: -len(".glb")]
        out = os.path.join(OUT, "characters", name + ".usdz")
        clips[name] = convert_character(os.path.join(SRC_CHARACTERS, f), out)
        print(f"character {name}: {len(clips[name]['clips'])} clips")

    for f in sorted(os.listdir(SRC_FURNITURE)):
        if not f.endswith(".glb"):
            continue
        name = f[: -len(".glb")]
        convert_static(
            os.path.join(SRC_FURNITURE, f),
            os.path.join(OUT, "furniture", name + ".usdz"),
        )
        print(f"furniture {name}")

    with open(os.path.join(OUT, "clips.json"), "w") as fh:
        json.dump(clips, fh, indent=2, sort_keys=True)
        fh.write("\n")


try:
    main()
except Exception as exc:  # make failures visible in headless runs
    print(f"convert-assets failed: {exc}", file=sys.stderr)
    sys.exit(1)
