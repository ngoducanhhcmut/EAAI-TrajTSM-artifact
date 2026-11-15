"""
nuScenes data loader — converts nuScenes scene annotations into
VLA-Traj world model tokens (bbox6_t format) and extracts GT future waypoints.

Token format (planning_pkg.sv bbox6_t):
  (x_min, y_min, x_max, y_max, vx, vy)  — all in current ego frame (metres, m/s)

Token ordering (closer to world_model_parser.sv):
  [0]   CLS token    : all zeros
  [1]   EGO token    : ego vehicle bbox + velocity (always in ego frame → centred)
  [2..] OBJECT tokens: nearby detected objects, sorted by distance
  [..]  LANE tokens  : optional lane-centerline snippets from nuScenes HD map
  [N]   TARGET token : optional proxy navigation target encoded as
                       {target_x, target_y, 0, 0, 0, 0}
  Fill remaining slots to MAX_SEQ_LEN=64 with zero-padding (mask=True for padding)

GT waypoints:
  Future ego positions at +0.5s, +1.0s, +1.5s, +2.0s (4 samples at 2 Hz).
  Expressed as (x, y) offsets in the current ego frame.

Requirements: pip install nuscenes-devkit pyquaternion
"""

from __future__ import annotations

import numpy as np
from functools import lru_cache
from typing import Iterable, List, Optional, Set, Tuple
from pyquaternion import Quaternion

MAX_SEQ_LEN   = 64
NUM_WAYPOINTS = 4    # 4 future samples = 2 s horizon at 2 Hz
EGO_LENGTH    = 4.6  # metres (typical passenger car)
EGO_WIDTH     = 2.0

# Objects further than this threshold are dropped from the token sequence
MAX_OBJECT_RANGE_M = 50.0
LANE_SEARCH_RADIUS_M = 50.0   # increased from 30m for more map context
MAX_LANE_TOKENS = 8            # increased from 4 for richer lane coverage


def _get_map_name(nusc, sample_token: str) -> str:
    sample = nusc.get("sample", sample_token)
    scene = nusc.get("scene", sample["scene_token"])
    log = nusc.get("log", scene["log_token"])
    return log["location"]


@lru_cache(maxsize=8)
def _load_map_api(dataroot: str, map_name: str):
    from nuscenes.map_expansion.map_api import NuScenesMap
    return NuScenesMap(dataroot=dataroot, map_name=map_name)


def _build_lane_tokens(
    nusc,
    sample_token: str,
    ego_t: np.ndarray,
    ego_r: Quaternion,
    max_lanes: int = MAX_LANE_TOKENS,
    radius_m: float = LANE_SEARCH_RADIUS_M,
) -> List[np.ndarray]:
    """
    Build lane tokens from the nuScenes map expansion pack.

    Token encoding follows the RTL lane-token intent:
      {wp0_x, wp0_y, wp1_x, wp1_y, 0.0, lane_type}
    where lane_type is encoded as:
      0.0 -> lane
      1.0 -> lane_connector
    """
    dataroot = getattr(nusc, "dataroot", None)
    if dataroot is None:
        return []

    map_name = _get_map_name(nusc, sample_token)
    nmap = _load_map_api(dataroot, map_name)
    records = nmap.get_records_in_radius(
        ego_t[0], ego_t[1], radius_m, ["lane", "lane_connector"], mode="intersect"
    )

    candidates = []
    for layer_name in ("lane", "lane_connector"):
        tokens = records.get(layer_name, [])
        if not tokens:
            continue
        centerlines = nmap.discretize_lanes(tokens, resolution_meters=2.0)
        for lane_token in tokens:
            pts = centerlines.get(lane_token, [])
            if len(pts) < 2:
                continue

            pts_global = np.array([[p[0], p[1], 0.0] for p in pts], dtype=np.float32)
            pts_ego = _global_to_ego(pts_global, ego_t, ego_r)
            dists = np.hypot(pts_ego[:, 0], pts_ego[:, 1])
            idx = int(np.argmin(dists))
            p0 = pts_ego[idx]
            if idx + 1 < len(pts_ego):
                p1 = pts_ego[idx + 1]
            elif idx > 0:
                p1 = pts_ego[idx - 1]
            else:
                continue

            lane_type = 1.0 if layer_name == "lane_connector" else 0.0
            tok = np.array(
                [p0[0], p0[1], p1[0], p1[1], 0.0, lane_type],
                dtype=np.float32,
            )
            candidates.append((float(dists[idx]), tok))

    candidates.sort(key=lambda x: x[0])
    return [tok for _, tok in candidates[:max_lanes]]


def _get_ego_pose(nusc, sample_token: str) -> Tuple[np.ndarray, Quaternion]:
    """Return (translation [3,], rotation Quaternion) for ego at this sample."""
    sample = nusc.get("sample", sample_token)
    lidar_token = sample["data"]["LIDAR_TOP"]
    sd = nusc.get("sample_data", lidar_token)
    ep = nusc.get("ego_pose", sd["ego_pose_token"])
    return np.array(ep["translation"]), Quaternion(ep["rotation"])


def _global_to_ego(
    pts_global: np.ndarray,     # (..., 3) in global frame
    ego_t: np.ndarray,          # (3,) ego translation
    ego_r: Quaternion,          # ego rotation
) -> np.ndarray:
    """Transform points from global frame to current ego frame."""
    pts = pts_global - ego_t                    # translate
    inv = ego_r.inverse
    pts = np.array([inv.rotate(p) for p in pts.reshape(-1, 3)]).reshape(pts.shape)
    return pts


def _vel_global_to_ego(vel_global: np.ndarray, ego_r: Quaternion) -> np.ndarray:
    """Rotate velocity vector from global to ego frame (no translation)."""
    inv = ego_r.inverse
    if vel_global.ndim == 1:
        return np.array(inv.rotate(vel_global))
    return np.array([inv.rotate(v) for v in vel_global])


def build_tokens_for_sample(
    nusc,
    sample_token: str,
    target_xy: Optional[np.ndarray] = None,
    include_lane_tokens: bool = True,
    max_lanes: int = MAX_LANE_TOKENS,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    Build (tokens, padding_mask) for one nuScenes sample.

    Returns:
      tokens       : (MAX_SEQ_LEN, 6) float32  — bbox6_t in ego frame
      padding_mask : (MAX_SEQ_LEN,)   bool      — True = padding slot
    """
    sample   = nusc.get("sample", sample_token)
    ego_t, ego_r = _get_ego_pose(nusc, sample_token)
    inv_r    = ego_r.inverse
    lane_tokens = []
    if include_lane_tokens:
        lane_tokens = _build_lane_tokens(
            nusc, sample_token, ego_t=ego_t, ego_r=ego_r, max_lanes=max_lanes
        )
    max_objects = MAX_SEQ_LEN - 3 - len(lane_tokens)   # leave room for CLS + EGO + TARGET

    tokens = np.zeros((MAX_SEQ_LEN, 6), dtype=np.float32)
    mask   = np.ones(MAX_SEQ_LEN, dtype=bool)    # all padding by default

    # ── Token 0: CLS (all zeros, always valid) ───────────────────────────────
    tokens[0] = 0.0
    mask[0]   = False

    # ── Token 1: EGO vehicle ─────────────────────────────────────────────────
    # Ego velocity estimated from previous keyframe displacement (0.5 s apart).
    # Previous sample ego pose → current ego pose → delta in current ego frame.
    # Falls back to (0, 0) for the first frame in a scene (no prev).
    ego_vx, ego_vy = 0.0, 0.0
    if sample.get("prev", "") != "":
        try:
            prev_t, _ = _get_ego_pose(nusc, sample["prev"])
            cur_sample = nusc.get("sample", sample_token)
            prev_sample = nusc.get("sample", sample["prev"])
            dt = (cur_sample["timestamp"] - prev_sample["timestamp"]) * 1e-6  # µs → s
            if dt > 0.01:  # guard against bad timestamps
                delta_global = ego_t - prev_t                     # (3,) global frame
                delta_ego    = np.array(inv_r.rotate(delta_global))  # → ego frame
                ego_vx = float(delta_ego[0] / dt)
                ego_vy = float(delta_ego[1] / dt)
        except KeyError:
            pass

    tokens[1] = np.array([
        -EGO_LENGTH / 2, -EGO_WIDTH / 2,
         EGO_LENGTH / 2,  EGO_WIDTH / 2,
        ego_vx, ego_vy,   # ego velocity in current ego frame (m/s)
    ], dtype=np.float32)
    mask[1] = False

    # ── Tokens 2..: Surrounding objects ──────────────────────────────────────
    slot = 2
    ann_tokens = sample["anns"]

    # Collect objects with their distance for sorting
    objects = []
    for ann_token in ann_tokens:
        ann = nusc.get("sample_annotation", ann_token)

        # Convert centre to ego frame
        centre_global = np.array(ann["translation"])   # (3,)
        centre_ego    = np.array(inv_r.rotate(centre_global - ego_t))  # (3,)

        dist = float(np.hypot(centre_ego[0], centre_ego[1]))
        if dist > MAX_OBJECT_RANGE_M:
            continue

        # Half-extents of the bounding box (nuScenes size: [W, L, H])
        wlh = ann["size"]              # [width, length, height] in local frame
        hw  = wlh[0] / 2.0            # half-width
        hl  = wlh[1] / 2.0            # half-length

        x_min = centre_ego[0] - hl
        y_min = centre_ego[1] - hw
        x_max = centre_ego[0] + hl
        y_max = centre_ego[1] + hw

        # Velocity
        vel = nusc.box_velocity(ann_token)     # (3,) in global frame; NaN if not moving
        if np.any(np.isnan(vel)):
            vel = np.zeros(3)
        vel_ego = np.array(inv_r.rotate(vel))
        vx, vy  = float(vel_ego[0]), float(vel_ego[1])

        objects.append((dist, np.array([x_min, y_min, x_max, y_max, vx, vy],
                                       dtype=np.float32)))

    # Sort by distance, keep nearest max_objects
    objects.sort(key=lambda t: t[0])
    for _, tok_vec in objects[:max_objects]:
        if slot >= MAX_SEQ_LEN:
            break
        tokens[slot] = tok_vec
        mask[slot]   = False
        slot += 1

    for lane_tok in lane_tokens:
        if slot >= MAX_SEQ_LEN:
            break
        tokens[slot] = lane_tok
        mask[slot] = False
        slot += 1

    if target_xy is not None and slot < MAX_SEQ_LEN:
        tokens[slot] = np.array(
            [target_xy[0], target_xy[1], 0.0, 0.0, 0.0, 0.0],
            dtype=np.float32,
        )
        mask[slot] = False

    return tokens, mask


def get_gt_waypoints(
    nusc,
    sample_token: str,
) -> Optional[np.ndarray]:
    """
    Extract 4 future ego positions (x, y) in current ego frame.

    Follows the future sample chain: sample → next → next → next → next.
    If fewer than NUM_WAYPOINTS future samples exist, returns None.

    Returns: (NUM_WAYPOINTS, 2) float32  — (x, y) in current ego frame (metres)
             or None if insufficient future samples.
    """
    ego_t, ego_r = _get_ego_pose(nusc, sample_token)
    inv_r = ego_r.inverse

    waypoints = []
    cur_token = sample_token
    for _ in range(NUM_WAYPOINTS):
        cur_sample = nusc.get("sample", cur_token)
        if cur_sample["next"] == "":
            return None    # not enough future frames
        cur_token = cur_sample["next"]

        fut_t, _ = _get_ego_pose(nusc, cur_token)
        # Transform future position to current ego frame
        fut_ego = np.array(inv_r.rotate(fut_t - ego_t))
        waypoints.append(fut_ego[:2])   # (x, y) only

    return np.array(waypoints, dtype=np.float32)   # (4, 2)


def _resolve_split(split: str) -> str:
    """
    Resolve a requested split name to one available in the installed devkit.
    Handles v1.0-mini ("mini_train" / "mini_val") vs v1.0-trainval ("train" / "val").
    """
    from nuscenes.utils.splits import create_splits_scenes
    scene_splits = create_splits_scenes()
    if split in scene_splits:
        return split
    # trainval <-> mini fallback
    fallback_map = {
        "val":   ["mini_val",   "val"],
        "train": ["mini_train", "train"],
    }
    for candidate in fallback_map.get(split, []):
        if candidate in scene_splits:
            return candidate
    # last resort: first available key
    return list(scene_splits.keys())[0]


def load_nuscenes_samples(
    nusc,
    num_scenes: int = 200,
    split: str = "val",
    scene_offset: int = 0,
    exclude_scene_names: Optional[Iterable[str]] = None,
    samples_per_scene: int = 1,
    include_lane_tokens: bool = True,
    include_target_token_proxy: bool = False,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Load up to ``num_scenes`` sample-level examples from nuScenes.

    By default (samples_per_scene=1) one keyframe per scene is taken to avoid
    temporal correlation, which is ideal for a large dataset (v1.0-trainval).

    When working with v1.0-mini (only 10 scenes total) set samples_per_scene>1
    so that multiple keyframes from each scene are collected until num_scenes
    total samples are accumulated.  For example:
        load_nuscenes_samples(nusc, num_scenes=200, split="val",
                              samples_per_scene=70)
    pulls up to 70 keyframes per scene from the 3 mini-val scenes.

    Args:
      nusc             : NuScenes instance
      num_scenes       : total samples to collect (stops early if exhausted)
      split            : "train" / "val" / "mini_train" / "mini_val"
      scene_offset     : scenes to skip at the start of the split
      exclude_scene_names: scene names to exclude
      samples_per_scene: max keyframes to take from each scene (default 1)
      include_lane_tokens: include lane snippets from nuScenes HD map
      include_target_token_proxy: append GT-final-waypoint proxy as TARGET token

    Returns:
      tokens_all  : (N, 64, 6)  float32
      masks_all   : (N, 64)     bool
      gt_wp_all   : (N, 4, 2)   float32
    """
    from nuscenes.utils.splits import create_splits_scenes

    target_split = _resolve_split(split)
    split_scenes = set(create_splits_scenes()[target_split])

    tokens_list: List[np.ndarray] = []
    masks_list:  List[np.ndarray] = []
    gt_list:     List[np.ndarray] = []
    exclude_set: Set[str] = set(exclude_scene_names or [])
    skipped = 0

    for scene in nusc.scene:
        if len(tokens_list) >= num_scenes:
            break
        if scene["name"] not in split_scenes or scene["name"] in exclude_set:
            continue
        if skipped < scene_offset:
            skipped += 1
            continue

        count_this_scene = 0
        sample_token = scene["first_sample_token"]
        while sample_token != "" and len(tokens_list) < num_scenes:
            if count_this_scene >= samples_per_scene:
                break
            sample = nusc.get("sample", sample_token)
            gt_wp  = get_gt_waypoints(nusc, sample_token)
            if gt_wp is not None:
                target_xy = gt_wp[-1] if include_target_token_proxy else None
                tokens, mask = build_tokens_for_sample(
                    nusc,
                    sample_token,
                    target_xy=target_xy,
                    include_lane_tokens=include_lane_tokens,
                )
                tokens_list.append(tokens)
                masks_list.append(mask)
                gt_list.append(gt_wp)
                count_this_scene += 1
            sample_token = sample["next"]

    if not tokens_list:
        raise RuntimeError(
            f"No valid samples found in split '{target_split}'. "
            "Check nuScenes dataroot and split name."
        )

    print(
        f"Loaded {len(tokens_list)} samples from nuScenes "
        f"({target_split}, samples_per_scene={samples_per_scene}, "
        f"scene_offset={scene_offset}, excluded={len(exclude_set)})."
    )
    return (
        np.stack(tokens_list, axis=0).astype(np.float32),
        np.stack(masks_list,  axis=0),
        np.stack(gt_list,     axis=0).astype(np.float32),
    )


def load_nuscenes_all_samples(
    nusc,
    split: str = "val",
    samples_per_scene: int = 1,
    include_lane_tokens: bool = True,
    include_target_token_proxy: bool = False,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Load ALL samples from nuScenes (or samples_per_scene per scene).
    Results are disk-cached as .npy files keyed by (version, split,
    samples_per_scene, include_lane_tokens, include_target_token_proxy).
    First run is slow (lane-token map queries); subsequent runs are instant.
    """
    import hashlib, os

    from nuscenes.utils.splits import create_splits_scenes

    target_split = _resolve_split(split)

    # --- cache key ---
    version  = getattr(nusc, "version", "unknown")
    dataroot = getattr(nusc, "dataroot", ".")
    key = f"{version}_{target_split}_sps{samples_per_scene}_lane{int(include_lane_tokens)}_tgt{int(include_target_token_proxy)}"
    cache_dir  = os.path.join(dataroot, "_token_cache")
    cache_stem = os.path.join(cache_dir, hashlib.md5(key.encode()).hexdigest())
    c_tok  = cache_stem + "_tokens.npy"
    c_mask = cache_stem + "_masks.npy"
    c_gt   = cache_stem + "_gt.npy"

    if os.path.exists(c_tok) and os.path.exists(c_mask) and os.path.exists(c_gt):
        print(f"  [cache hit] {key}", flush=True)
        return np.load(c_tok), np.load(c_mask), np.load(c_gt)

    print(f"  [cache miss — building tokens for {target_split}, sps={samples_per_scene}] ...",
          flush=True)

    split_scenes = set(create_splits_scenes()[target_split])
    tokens_list: List[np.ndarray] = []
    masks_list:  List[np.ndarray] = []
    gt_list:     List[np.ndarray] = []

    done = 0
    for scene in nusc.scene:
        if scene["name"] not in split_scenes:
            continue
        count = 0
        sample_token = scene["first_sample_token"]
        while sample_token != "" and count < samples_per_scene:
            sample = nusc.get("sample", sample_token)
            gt_wp  = get_gt_waypoints(nusc, sample_token)
            if gt_wp is not None:
                target_xy = gt_wp[-1] if include_target_token_proxy else None
                tokens, mask = build_tokens_for_sample(
                    nusc, sample_token,
                    target_xy=target_xy,
                    include_lane_tokens=include_lane_tokens,
                )
                tokens_list.append(tokens)
                masks_list.append(mask)
                gt_list.append(gt_wp)
                count += 1
                done += 1
                if done % 500 == 0:
                    print(f"    {done} samples built ...", flush=True)
            sample_token = sample["next"]

    arr_tok  = np.stack(tokens_list, axis=0).astype(np.float32)
    arr_mask = np.stack(masks_list,  axis=0)
    arr_gt   = np.stack(gt_list,     axis=0).astype(np.float32)

    os.makedirs(cache_dir, exist_ok=True)
    np.save(c_tok,  arr_tok)
    np.save(c_mask, arr_mask)
    np.save(c_gt,   arr_gt)
    print(f"  [saved token cache] {done} samples -> {cache_dir}", flush=True)

    return arr_tok, arr_mask, arr_gt
