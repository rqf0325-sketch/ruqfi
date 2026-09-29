"""Extracts the scripts of a binary .rbxm (Studio model file) into plain .luau files
plus a manifest.json that describes the tree (names, classes, Disabled flags).

Roblox's newest .rbxm files use property types that Lune cannot read yet, so this
small reader covers just what the AutoLights build needs.

  pip install lz4
  python3 tools/autolights/extract.py <model.rbxm> <out-dir>
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import rbxm  # noqa: E402


def main(path, outdir):
    cls_of, props, parent = rbxm.parse(path)
    os.makedirs(outdir, exist_ok=True)

    def name(ref):
        return props.get(ref, {}).get("Name", b"?").decode("utf-8")

    def path_of(ref):
        parts = []
        while ref != -1:
            parts.append(name(ref))
            ref = parent.get(ref, -1)
        return list(reversed(parts))

    children = {}
    for ref, par in parent.items():
        children.setdefault(par, []).append(ref)

    def node(ref):
        item = {"name": name(ref), "class": cls_of[ref]}
        info = props.get(ref, {})
        if cls_of[ref] in ("Script", "LocalScript", "ModuleScript"):
            item["disabled"] = bool(info.get("Disabled", 0))
            fname = ".".join(path_of(ref)) + ".luau"
            with open(os.path.join(outdir, fname), "wb") as handle:
                handle.write(info.get("Source", b""))
            item["file"] = fname
        kids = sorted(children.get(ref, []), key=name)
        if kids:
            item["children"] = [node(kid) for kid in kids]
        return item

    roots = [ref for ref in cls_of if parent.get(ref, -1) == -1]
    with open(os.path.join(outdir, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump([node(ref) for ref in sorted(roots, key=name)], handle, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
