#!/usr/bin/env python3
"""Register the bundled Native Messaging host for the current user, without sudo."""
import argparse
import json
import os
from pathlib import Path
import re
import tempfile

HOST = "com.rogerleite.macvolume.chrome"
DEFAULT_DIRECTORY = Path.home() / "Library/Application Support/Google/Chrome/NativeMessagingHosts"


def install(extension_id, app, directory=DEFAULT_DIRECTORY, replace=False):
    if not re.fullmatch(r"[a-p]{32}", extension_id):
        raise ValueError("Extension ID must contain exactly 32 lowercase letters a–p (from chrome://extensions).")
    app = Path(app).expanduser().resolve(strict=True)
    bridge = app / "Contents/MacOS/ChromeBridge"
    extension = app / "Contents/Resources/ChromeExtension/manifest.json"
    if app.suffix != ".app" or not bridge.is_file() or not os.access(bridge, os.X_OK) or not extension.is_file():
        raise ValueError("Build MacVolume.app first; the app must include ChromeBridge and ChromeExtension.")
    manifest = {"name": HOST, "description": "MacVolume Chrome tab controls", "path": str(bridge),
                "type": "stdio", "allowed_origins": [f"chrome-extension://{extension_id}/"]}
    directory = Path(directory).expanduser()
    destination = directory / f"{HOST}.json"
    if destination.is_symlink():
        raise ValueError("Refusing to replace a symlink at the host registration path.")
    if destination.exists():
        old = json.loads(destination.read_text())
        if old == manifest:
            return destination
        if not replace:
            raise ValueError("A different MacVolume bridge is registered. Review it, then use --replace to update it.")
        if old.get("name") != HOST:
            raise ValueError("Existing registration does not belong to MacVolume.")
    directory.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=directory, delete=False) as output:
            temporary = Path(output.name)
            json.dump(manifest, output, indent=2)
            output.write("\n")
        temporary.replace(destination)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("extension_id")
    parser.add_argument("--app", type=Path, required=True, help="Stable path to MacVolume.app")
    parser.add_argument("--host-directory", type=Path, default=DEFAULT_DIRECTORY,
                        help="Override for Chrome custom user-data directories or isolated testing")
    parser.add_argument("--replace", action="store_true", help="Replace a reviewed MacVolume registration")
    args = parser.parse_args()
    try:
        path = install(args.extension_id, args.app, args.host_directory, args.replace)
    except (ValueError, OSError) as error:
        parser.exit(1, f"{error}\n")
    print(f"Registered: {path}\nOpen MacVolume, then click Reconnect in MacVolume Tabs.")


if __name__ == "__main__":
    main()
