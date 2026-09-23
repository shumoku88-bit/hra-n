#!/usr/bin/env python3
"""Apply the two GtkAda 26 access-conversion fixes already present upstream.

GtkAda v26.0.0 contains two expression functions in gtkada-canvas_view.ads
whose anonymous access parameters are returned without an explicit conversion.
Current GNAT rejects those implicit conversions.  GtkAda upstream has since
changed both expressions to Abstract_Item (Self).

This script is intentionally narrow:
- it only edits gtkada-canvas_view.ads,
- it only replaces the exact v26.0.0 spelling,
- it is idempotent,
- it fails if GtkAda is present but neither old nor fixed spelling is found.
"""

from pathlib import Path
import sys

OLD = "return Abstract_Item is (Self);"
NEW = "return Abstract_Item is (Abstract_Item (Self));"

candidates = list(Path(".").rglob("gtkada-canvas_view.ads"))

if not candidates:
    print("hra-n-gui: GtkAda source not deployed yet; no compatibility patch needed")
    sys.exit(0)

patched = 0
recognized = 0

for path in candidates:
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
