#!/usr/bin/env python3
"""Remove only WinMix's current-user Native Messaging registration."""
import argparse
import json
from pathlib import Path

HOST = "com.rogerleite.macvolume.chrome"
DEFAULT_DIRECTORY = Path.home() / "Library/Application Support/Google/Chrome/NativeMessagingHosts"


def uninstall(directory=DEFAULT_DIRECTORY):
    path = Path(directory).expanduser() / f"{HOST}.json"
    if path.is_symlink():
        raise ValueError("Refusing to remove a symlink at the host registration path.")
    if not path.exists():
        return False
    if json.loads(path.read_text()).get("name") != HOST:
        raise ValueError("Registration does not belong to WinMix.")
    path.unlink()
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host-directory", type=Path, default=DEFAULT_DIRECTORY)
    args = parser.parse_args()
    try:
        removed = uninstall(args.host_directory)
    except (ValueError, OSError) as error:
        parser.exit(1, f"{error}\n")
    print("WinMix bridge registration removed." if removed else "WinMix bridge was not registered.")


if __name__ == "__main__":
    main()
