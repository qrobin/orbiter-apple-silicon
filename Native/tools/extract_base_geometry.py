#!/usr/bin/env python3
"""Regenerate the original landing-pad vertex/index tables; not a build dependency."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[2]
source = (root / "Src/Orbiter/Baseobj.cpp").read_text()
vertices = re.search(r"NTVERTEX Lpad02a::Vtx\[37\] = \{(.*?)\n\};", source, re.S).group(1)
indices = re.search(r"WORD Lpad02a::Idx\[96\] = \{(.*?)\n\};", source, re.S).group(1)
(root / "Native/BaseGeometry.inc").write_text(
    "// Original Lpad02a geometry from Src/Orbiter/Baseobj.cpp.\n"
    "// Copyright (c) Martin Schweiger, MIT License.\n"
    "static const Vertex padVertices[] = {" + vertices + "\n};\n"
    "static const uint32_t padIndices[] = {" + indices + "\n};\n")
