"""Packages a built .app into an unsigned IPA that Sideloadly / AltStore / TrollStore can sign.

Usage:
    python3 scripts/make_unsigned_ipa.py <path/to/MagdyBrowser.app> <output.ipa>
"""

import os
import shutil
import sys
import zipfile


def build_ipa(app_path: str, output_path: str) -> None:
    app_path = os.path.abspath(app_path)
    if not os.path.isdir(app_path):
        sys.exit(f"app not found: {app_path}")

    staging = os.path.join(os.path.dirname(output_path), "_staging")
    payload = os.path.join(staging, "Payload")
    if os.path.isdir(staging):
        shutil.rmtree(staging)
    os.makedirs(payload)

    shutil.copytree(app_path, os.path.join(payload, os.path.basename(app_path)),
                    symlinks=True)

    if os.path.isdir(output_path):
        os.remove(output_path)

    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for root, _dirs, files in os.walk(staging):
            for name in files:
                full = os.path.join(root, name)
                relative = os.path.relpath(full, staging)
                archive.write(full, relative.replace(os.sep, "/"))

    shutil.rmtree(staging)
    print(f"wrote {output_path} ({os.path.getsize(output_path) // 1024} KB)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    build_ipa(sys.argv[1], sys.argv[2])
