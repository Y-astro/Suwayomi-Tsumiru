import importlib.util
from pathlib import Path
import tempfile
import unittest
import warnings
import zipfile

spec = importlib.util.spec_from_file_location("retry_package", Path(__file__).with_name("package_update_retries.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.base = self.root / "base.jar"
        self.output = self.root / "candidate.jar"
        self.classes = self.root / "classes"
        self.patch = self.root / "source.patch"
        self.patch.write_text("reviewed sources")
        with warnings.catch_warnings(), zipfile.ZipFile(self.base, "w") as jar:
            warnings.simplefilter("ignore", UserWarning)
            jar.writestr(module.OWNERS[0] + ".class", b"old")
            jar.writestr(module.OWNERS[0] + "$Obsolete.class", b"old nested")
            jar.writestr("suwayomi/tachidesk/manga/impl/Manga.class", b"existing manga")
            jar.writestr("suwayomi/tachidesk/manga/impl/update/IUpdater.class", b"existing interface")
            jar.writestr("META-INF/MANIFEST.MF", "existing manifest")
            jar.writestr("META-INF/mobile-server-build.json", "existing fixes")
            jar.writestr("META-INF/tsumiru-library-update-retries.json", "prior provenance")
            jar.writestr("duplicate", "first")
            jar.writestr("duplicate", "second")
        for owner in module.OWNERS:
            path = self.classes / (owner + ".class")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"\xca\xfe\xba\xbe\0\0\0A")

    def package(self, **kwargs):
        return module.package(self.base, self.classes, self.output, self.patch,
                              expected_sha=kwargs.get("sha", module.digest(self.base)))

    def test_existing_manga_and_interface_are_outside_recovery_overlay(self):
        for name in ("Manga", "MangaKt"):
            self.assertFalse(module.owned("suwayomi/tachidesk/manga/impl/" + name + ".class"))
        self.assertFalse(module.owned("suwayomi/tachidesk/manga/impl/update/IUpdater.class"))

    def test_preserves_every_unrelated_occurrence_and_removes_obsolete_classes(self):
        self.package()
        with zipfile.ZipFile(self.base) as old, zipfile.ZipFile(self.output) as new:
            self.assertEqual(module.preserved(old), module.preserved(new))
            self.assertNotIn(module.OWNERS[0] + "$Obsolete.class", new.namelist())
            self.assertIn(module.METADATA, new.namelist())
            self.assertIn("META-INF/tsumiru-library-update-retries.json", new.namelist())

    def test_refuses_unknown_base_missing_class_and_wrong_target(self):
        with self.assertRaisesRegex(ValueError, "Base JAR differs"):
            self.package(sha="0" * 64)
        path = self.classes / (module.OWNERS[0] + ".class")
        path.unlink()
        with self.assertRaisesRegex(ValueError, "Missing reviewed"):
            self.package()
        path.write_bytes(b"\xca\xfe\xba\xbe\0\0\0B")
        with self.assertRaisesRegex(ValueError, "Java 21"):
            self.package()
        self.assertFalse(self.output.exists())

    def test_refuses_overwrite_and_ambiguous_classes(self):
        self.package()
        with self.assertRaisesRegex(ValueError, "Output already exists"):
            self.package()
        self.output.unlink()
        with warnings.catch_warnings(), zipfile.ZipFile(self.base, "a") as jar:
            warnings.simplefilter("ignore", UserWarning)
            jar.writestr(module.OWNERS[0] + ".class", b"duplicate")
        with self.assertRaisesRegex(ValueError, "Ambiguous original"):
            self.package()


if __name__ == "__main__":
    unittest.main()
