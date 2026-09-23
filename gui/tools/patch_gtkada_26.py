#!/usr/bin/env python3
"""Apply the two GtkAda 26 access-conversion fixes already present upstream.

GtkAda v26.0.0 contains two expression functions in gtkada-canvas_view.ads
whose anonymous access parameters are returned without an explicit conversion.
Current GNAT rejects those implicit conversions. GtkAda upstream has since
changed both expressions to Abstract_Item (Self).

This script is intentionally narrow:
- it only edits gtkada-canvas_view.ads,
- it only replaces the exact v26.0.0 spelling,
- it is idempotent,
- it finds both sandboxed and Alire 2 shared dependency builds,
- it refuses unfamiliar source shapes.
"""

from pathlib import Path
import os
import sys

OLD = "return Abstract_Item is (Self);"
NEW = "return Abstract_Item is (Abstract_Item (Self));"

roots: set[Path] = {Path.cwd()}

# Alire exposes project search paths to the build. These commonly point
# directly into the selected dependency build, which is the best target.
for entry in os.environ.get("GPR_PROJECT_PATH", "").split(os.pathsep):
    if entry:
        p = Path(entry).expanduser()
        roots.add(p)
        roots.add(p.parent)

# Alire 2 defaults to shared dependencies outside the workspace.
for cache_name in ("builds", "releases"):
    cache = Path.home() / ".cache" / "alire" / cache_name
    if cache.is_dir():
        for p in cache.glob("gtkada*"):
            roots.add(p)

candidates: set[Path] = set()
for root in roots:
    if not root.exists():
        continue

    direct = (
        root / "src" / "gtkada-canvas_view.ads",
        root / "src" / "gtk3" / "gtkada-canvas_view.ads",
        root / "gtkada-canvas_view.ads",
    )
    for path in direct:
        if path.is_file():
            candidates.add(path)

    # Only recurse roots that are clearly GtkAda deployments/builds, avoiding
    # an expensive walk of the user's home or entire shared cache.
    if "gtkada" in root.name.lower():
        for path in root.rglob("gtkada-canvas_view.ads"):
            if path.is_file():
                candidates.add(path)

if not candidates:
    print(
        "hra-n-gui: could not locate the Alire-deployed GtkAda source; "
        "GPR_PROJECT_PATH=" + os.environ.get("GPR_PROJECT_PATH", "<unset>"),
        file=sys.stderr,
    )
    sys.exit(1)

patched = 0
recognized = 0

for path in sorted(candidates):
    text = path.read_text(encoding="utf-8")
    old_count = text.count(OLD)
    new_count = text.count(NEW)

    if old_count:
        # GtkAda v26.0.0 has exactly two occurrences.
        if old_count != 2:
            print(
                f"hra-n-gui: refusing unexpected GtkAda source shape in {path}: "
                f"found {old_count} legacy conversions, expected 2",
                file=sys.stderr,
            )
            sys.exit(1)
        path.write_text(text.replace(OLD, NEW), encoding="utf-8")
        patched += old_count
        recognized += 1
        print(f"hra-n-gui: patched GtkAda 26 access conversions in {path}")
    elif new_count >= 2:
        recognized += 1
        print(f"hra-n-gui: GtkAda access conversions already fixed in {path}")

if recognized == 0:
    print(
        "hra-n-gui: GtkAda canvas source found, but its access-conversion "
        "shape is unknown; refusing to patch",
        file=sys.stderr,
    )
    sys.exit(1)

print(f"hra-n-gui: GtkAda compatibility patch complete ({patched} edits)")
