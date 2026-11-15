"""
NuScenesLite -- memory-efficient nuScenes loader for annotation-only access.

The official nuscenes-devkit loads ALL tables including sample_data.json
(1.28 GB uncompressed for v1.0-trainval) into RAM at startup, which
causes MemoryError on machines with ~16 GB RAM.

We only need 5 tables for our pipeline:
  scene.json              0.3 MB   -- scene list
  sample.json             7.1 MB   -- keyframe list
  sample_annotation.json  556 MB   -- bounding box annotations
  ego_pose.json           616 MB   -- ego vehicle pose at every sensor timestamp
  sample_data.json        1283 MB  -- sensor data entries (we stream, keep LIDAR_TOP kf only)

Strategy:
  1. Load scene / sample fully (small).
  2. Stream sample_data.json to extract LIDAR_TOP keyframe entries (~34k of ~2.6M).
     NOTE: trainval sample_data has no "channel" field; channel is in "filename".
  3. Build reverse indices: sample_token -> lidar_sd_token (for sample["data"]["LIDAR_TOP"])
  4. Load ego_pose.json streaming, keep only the ~34k tokens needed.
  5. Load sample_annotation.json fully (556 MB).
  6. Build reverse index: sample_token -> [ann_tokens] (for sample["anns"]).

Drop-in replacement for nuscenes.NuScenes for our specific use case.
Compatible with nuscenes_loader.py API.
"""

from __future__ import annotations
import json
import os
import pickle
from typing import Dict, Any, Set

import numpy as np
from pyquaternion import Quaternion

# Bump this when the cache schema changes to force a rebuild.
_CACHE_VERSION = 2


# ---------------------------------------------------------------------------
# Streaming helpers
# ---------------------------------------------------------------------------

def _stream_json_array(path: str):
    """
    Yield JSON objects from a file containing a top-level array [ {...}, {...}, ... ]
    without loading the entire file into memory.

    Reads in 8 MB chunks, finds complete JSON objects using brace counting.
    """
    buf      = ""
    depth    = 0
    in_str   = False
    escape   = False
    obj_start = -1

    with open(path, "r", encoding="utf-8") as fh:
        while True:
            chunk = fh.read(8 * 1024 * 1024)   # 8 MB
            if not chunk:
                break
            for ch in chunk:
                if escape:
                    escape = False
                elif ch == "\\" and in_str:
                    escape = True
                elif ch == '"':
                    in_str = not in_str
                elif not in_str:
                    if ch == "{":
                        if depth == 0:
                            obj_start = len(buf)
                        depth += 1
                    elif ch == "}":
                        depth -= 1
                        if depth == 0 and obj_start >= 0:
                            buf += ch
                            yield json.loads(buf[obj_start:])
                            buf = ""
                            obj_start = -1
                            continue
                buf += ch


def _load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# NuScenesLite
# ---------------------------------------------------------------------------

class NuScenesLite:
    """
    Drop-in replacement for nuscenes.NuScenes (annotation-only access).
    Works with nuscenes_loader.py without modification.

    Differences from raw JSON:
      - sample records are augmented with "data" and "anns" reverse-index fields
        (same as what the official devkit builds in memory).
    """

    def __init__(self, version: str, dataroot: str, verbose: bool = True):
        self.version  = version
        self.dataroot = dataroot
        base          = os.path.join(dataroot, version)

        if verbose:
            print(f"[NuScenesLite] Loading {version} from {dataroot} ...")

        # -- scene / log / sample  (always load fresh — small files) --
        if verbose: print("  scene.json ...", flush=True)
        self.scene = _load_json(os.path.join(base, "scene.json"))
        self._scene: Dict[str, Any] = {r["token"]: r for r in self.scene}

        if verbose: print("  log.json ...", flush=True)
        log_list = _load_json(os.path.join(base, "log.json"))
        self._log: Dict[str, Any] = {r["token"]: r for r in log_list}

        if verbose: print("  sample.json ...", flush=True)
        sample_list = _load_json(os.path.join(base, "sample.json"))
        self._sample: Dict[str, Any] = {r["token"]: r for r in sample_list}
        for rec in self._sample.values():
            rec.setdefault("data", {})
            rec.setdefault("anns", [])

        # ------------------------------------------------------------------
        # Large-table cache  (pickle, ~400 MB in memory, ~120 MB on disk)
        # First run: stream all three big files (~15 min).
        # Subsequent runs: load pickle in <5 seconds.
        # ------------------------------------------------------------------
        cache_path = os.path.join(base, f"_nuscenes_lite_v{_CACHE_VERSION}.pkl")

        if os.path.exists(cache_path):
            if verbose:
                print(f"  Loading from cache: {os.path.basename(cache_path)} ...",
                      flush=True)
            with open(cache_path, "rb") as f:
                cache = pickle.load(f)
            self._lidar_sd        = cache["lidar_sd"]
            self._ego_pose        = cache["ego_pose"]
            self._sample_annotation = cache["sample_annotation"]
            for st, sd_tok in cache["sample_lidar_map"].items():
                if st in self._sample:
                    self._sample[st]["data"]["LIDAR_TOP"] = sd_tok
            for st, anns in cache["sample_anns"].items():
                if st in self._sample:
                    self._sample[st]["anns"] = anns
            ann_count = len(self._sample_annotation)
            if verbose:
                print(f"[NuScenesLite] Ready (cached): {len(self.scene)} scenes, "
                      f"{len(self._sample)} samples, "
                      f"{len(self._ego_pose)} ego_poses, "
                      f"{ann_count} annotations.")
            return

        # ---- slow path: stream all three large files ----
        if verbose:
            print("  (First run — building cache, this takes ~15 min) ...", flush=True)

        # sample_data: LIDAR_TOP keyframes only
        if verbose:
            print("  sample_data.json (streaming LIDAR_TOP keyframes) ...", flush=True)
        self._lidar_sd: Dict[str, Any] = {}
        sample_lidar_map: Dict[str, str] = {}   # sample_token -> sd_token
        count = 0
        for obj in _stream_json_array(os.path.join(base, "sample_data.json")):
            if not obj.get("is_key_frame"):
                continue
            fname = obj.get("filename", obj.get("channel", ""))
            if "LIDAR_TOP" not in fname:
                continue
            sd_tok = obj["token"]
            st     = obj.get("sample_token", "")
            self._lidar_sd[sd_tok] = {
                "token":          sd_tok,
                "ego_pose_token": obj["ego_pose_token"],
                "sample_token":   st,
            }
            if st in self._sample:
                self._sample[st]["data"]["LIDAR_TOP"] = sd_tok
                sample_lidar_map[st] = sd_tok
            count += 1
        if verbose:
            print(f"    -> {count} LIDAR_TOP keyframe entries kept", flush=True)

        needed_ep: Set[str] = {v["ego_pose_token"] for v in self._lidar_sd.values()}

        # ego_pose: keep only needed tokens
        if verbose:
            print(f"  ego_pose.json (keeping {len(needed_ep)} entries) ...", flush=True)
        self._ego_pose: Dict[str, Any] = {}
        for obj in _stream_json_array(os.path.join(base, "ego_pose.json")):
            if obj["token"] in needed_ep:
                self._ego_pose[obj["token"]] = obj

        # sample_annotation: minimal fields only
        _ANN_KEEP = frozenset({"token", "sample_token", "translation", "size",
                               "prev", "next"})
        if verbose:
            print("  sample_annotation.json (streaming, minimal fields) ...", flush=True)
        self._sample_annotation: Dict[str, Any] = {}
        sample_anns: Dict[str, list] = {}
        ann_count = 0
        for obj in _stream_json_array(os.path.join(base, "sample_annotation.json")):
            slim = {k: obj[k] for k in _ANN_KEEP if k in obj}
            self._sample_annotation[slim["token"]] = slim
            st = slim.get("sample_token", "")
            if st in self._sample:
                self._sample[st]["anns"].append(slim["token"])
                sample_anns.setdefault(st, []).append(slim["token"])
            ann_count += 1
        if verbose:
            print(f"    -> {ann_count} annotations loaded", flush=True)

        # Save cache for future runs
        if verbose:
            print(f"  Saving cache -> {os.path.basename(cache_path)} ...", flush=True)
        with open(cache_path, "wb") as f:
            pickle.dump({
                "lidar_sd":          self._lidar_sd,
                "ego_pose":          self._ego_pose,
                "sample_annotation": self._sample_annotation,
                "sample_lidar_map":  sample_lidar_map,
                "sample_anns":       sample_anns,
            }, f, protocol=pickle.HIGHEST_PROTOCOL)

        if verbose:
            print(f"[NuScenesLite] Ready: {len(self.scene)} scenes, "
                  f"{len(self._sample)} samples, "
                  f"{len(self._ego_pose)} ego_poses, "
                  f"{ann_count} annotations (slim).")

    # ------------------------------------------------------------------
    # Public API (mirrors nuscenes.NuScenes)
    # ------------------------------------------------------------------

    def get(self, table_name: str, token: str) -> Any:
        table_map = {
            "sample":            self._sample,
            "sample_data":       self._lidar_sd,
            "ego_pose":          self._ego_pose,
            "sample_annotation": self._sample_annotation,
            "scene":             self._scene,
            "log":               self._log,
        }
        table = table_map.get(table_name)
        if table is None:
            raise KeyError(f"NuScenesLite: unknown table '{table_name}'")
        result = table.get(token)
        if result is None:
            raise KeyError(f"NuScenesLite: {table_name}[{token}] not found")
        return result

    def box_velocity(
        self,
        sample_annotation_token: str,
        max_time_diff: float = 1.5,
    ) -> np.ndarray:
        """
        Estimate 3-D velocity in the global frame.
        Matches nuscenes.NuScenes.box_velocity().
        Returns (3,) float or NaN array if unavailable.
        """
        current = self._sample_annotation.get(sample_annotation_token)
        if current is None:
            return np.array([np.nan, np.nan, np.nan])

        has_prev = current["prev"] != ""
        has_next = current["next"] != ""

        if not has_prev and not has_next:
            return np.array([np.nan, np.nan, np.nan])

        first = (self._sample_annotation[current["prev"]]
                 if has_prev else current)
        last  = (self._sample_annotation[current["next"]]
                 if has_next else current)

        pos_first = np.array(first["translation"])
        pos_last  = np.array(last["translation"])

        try:
            t_first = self._get_sample_timestamp(first["sample_token"])
            t_last  = self._get_sample_timestamp(last["sample_token"])
        except KeyError:
            return np.array([np.nan, np.nan, np.nan])

        time_diff = 1e-6 * (t_last - t_first)
        if abs(time_diff) > max_time_diff:
            return np.array([np.nan, np.nan, np.nan])
        if abs(time_diff) < 1e-6:
            return np.array([np.nan, np.nan, np.nan])

        return (pos_last - pos_first) / time_diff

    def _get_sample_timestamp(self, sample_token: str) -> int:
        return self._sample[sample_token]["timestamp"]


# ---------------------------------------------------------------------------
# Factory: return NuScenesLite for trainval, standard NuScenes for mini
# ---------------------------------------------------------------------------

def load_nuscenes(version: str, dataroot: str, verbose: bool = True):
    """
    Return NuScenesLite for large datasets (trainval), standard NuScenes for mini.
    Both have the same API surface used by nuscenes_loader.py.
    """
    if "mini" in version:
        from nuscenes.nuscenes import NuScenes
        return NuScenes(version=version, dataroot=dataroot, verbose=verbose)
    return NuScenesLite(version=version, dataroot=dataroot, verbose=verbose)
