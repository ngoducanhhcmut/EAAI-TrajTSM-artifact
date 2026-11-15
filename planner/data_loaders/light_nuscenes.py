"""
LightNuScenes — memory-efficient NuScenes wrapper for VLA-Traj training.

Skips loading large tables that our data loader does not use:
  - sample_data      (1.3 GB)  — sensor file paths, not needed for trajectory data
  - calibrated_sensor (3.2 MB) — sensor calibration, not needed

Reduces peak memory from ~10-15 GB to ~4-6 GB for v1.0-trainval.

Usage:
  from data.light_nuscenes import LightNuScenes
  nusc = LightNuScenes(version='v1.0-trainval', dataroot='data/nuscenes')
  # Use exactly like NuScenes — nusc.get(), nusc.scene, etc.
"""

from __future__ import annotations

from nuscenes.nuscenes import NuScenes


class LightNuScenes(NuScenes):
    """
    NuScenes subclass that skips heavy tables unused by our trajectory loader.

    Our data loader (nuscenes_loader.py) accesses:
      nusc.get("sample", ...)             → sample.json        7 MB
      nusc.get("scene", ...)              → scene.json       279 KB
      nusc.get("log", ...)                → log.json          12 KB
      nusc.get("ego_pose", ...)           → ego_pose.json    616 MB
      nusc.get("sample_annotation", ...) → sample_annotation.json  557 MB
      nusc.scene                          → scene list
      (map API loaded separately by _load_map_api)

    Tables we safely skip:
      sample_data.json        1.3 GB  — sensor file paths
      calibrated_sensor.json  3.2 MB  — sensor calibration
    """

    SKIP_TABLES = frozenset({"sample_data", "calibrated_sensor"})

    def __load_table__(self, table_name: str):  # type: ignore[override]
        if table_name in self.SKIP_TABLES:
            return []
        return super().__load_table__(table_name)
