import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}-chrome-bridge.py")
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


installer, uninstaller = module("install"), module("uninstall")


class InstallerTests(unittest.TestCase):
    def test_install_update_and_remove_in_isolation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = root / "App with spaces.app"
            bridge = app / "Contents/MacOS/ChromeBridge"
            bridge.parent.mkdir(parents=True)
            bridge.write_text("test binary")
            bridge.chmod(0o755)
            manifest = app / "Contents/Resources/ChromeExtension/manifest.json"
            manifest.parent.mkdir(parents=True)
            manifest.write_text("{}")
            hosts = root / "hosts"
            path = installer.install("a" * 32, app, hosts)
            value = json.loads(path.read_text())
            self.assertEqual(value["path"], str(bridge.resolve()))
            self.assertEqual(value["allowed_origins"], [f"chrome-extension://{'a' * 32}/"])
            self.assertEqual(installer.install("a" * 32, app, hosts), path)
            with self.assertRaises(ValueError):
                installer.install("b" * 32, app, hosts)
            installer.install("b" * 32, app, hosts, replace=True)
            with self.assertRaises(ValueError):
                installer.install("invalid", app, hosts)
            other = hosts / "other.json"
            other.write_text("{}")
            self.assertTrue(uninstaller.uninstall(hosts))
            self.assertTrue(other.exists())
            self.assertFalse(uninstaller.uninstall(hosts))

    def test_refuses_symlink_registration(self):
        with tempfile.TemporaryDirectory() as temporary:
            hosts = Path(temporary)
            target = hosts / "other.json"
            target.write_text("{}")
            (hosts / f"{installer.HOST}.json").symlink_to(target)
            with self.assertRaises(ValueError):
                uninstaller.uninstall(hosts)
            self.assertTrue(target.exists())


if __name__ == "__main__":
    unittest.main()
