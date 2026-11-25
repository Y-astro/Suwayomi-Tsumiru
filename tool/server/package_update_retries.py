#!/usr/bin/env python3
"""Overlay reviewed recovery and updater classes without replacing existing server fixes."""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import warnings
import zipfile

BASE_SHA256 = "a8f28de60db71e874e0930c5ba0abd8487dce7597b48abdc54bea146634676c3"
UPSTREAM_COMMIT = "40bc5da57820324ed0ae724cbbc020cc4673b594"
OWNERS = (
    "suwayomi/tachidesk/manga/impl/update/Updater",
    "suwayomi/tachidesk/manga/impl/update/LibraryUpdateRetries",
    "suwayomi/tachidesk/manga/impl/update/LibraryUpdateRetryState",
    "suwayomi/tachidesk/manga/impl/update/ExtensionUpdateSchedule",
    "suwayomi/tachidesk/manga/impl/update/RecoveryRetrySchedule",
    "suwayomi/tachidesk/manga/impl/update/RecoveryRetryState",
    "suwayomi/tachidesk/manga/impl/update/ServerRecoveryManager",
)
METADATA = "META-INF/tsumiru-server-recovery.json"


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def owned(name):
    return name.endswith(".class") and any(
        name == owner + ".class" or name.startswith(owner + "$") for owner in OWNERS
    )


def preserved(archive):
    # ZipInfo selects the exact occurrence, including upstream duplicate resources.
    return [
        (info.filename, info.external_attr, hashlib.sha256(archive.read(info)).hexdigest())
        for info in archive.infolist()
        if not owned(info.filename) and info.filename != METADATA
    ]


def package(base, classes, output, patch, expected_sha=BASE_SHA256):
    base, classes, output = Path(base), Path(classes), Path(output)
    if digest(base) != expected_sha:
        raise ValueError("Base JAR differs from the reviewed installed build")
    if output.exists() or output.is_symlink():
        raise ValueError("Output already exists")
    selected = {}
    for path in classes.rglob("*.class"):
        name = path.relative_to(classes).as_posix()
        if not owned(name):
            continue
        if path.is_symlink() or not path.resolve().is_relative_to(classes.resolve()):
            raise ValueError("Compiled class escapes its directory")
        body = path.read_bytes()
        if len(body) < 8 or body[:4] != b"\xca\xfe\xba\xbe" or int.from_bytes(body[6:8], "big") != 65:
            raise ValueError("Expected Java 21 class: " + name)
        selected[name] = body
    if any(owner + ".class" not in selected for owner in OWNERS):
        raise ValueError("Missing reviewed class owner")
    with zipfile.ZipFile(base) as old:
        names = old.namelist()
        if METADATA in names:
            raise ValueError("Server recovery patch already installed")
        if any(names.count(name) != 1 for name in names if owned(name)):
            raise ValueError("Ambiguous original class")
        provenance = {
            "format": 2,
            "base_jar_sha256": expected_sha,
            "upstream_commit": UPSTREAM_COMMIT,
            "source_patch_sha256": digest(patch),
            "class_sha256": {name: hashlib.sha256(body).hexdigest() for name, body in sorted(selected.items())},
        }
        stamp = old.getinfo("suwayomi/tachidesk/manga/impl/update/Updater.class").date_time
        created = False
        try:
            with output.open("xb") as target:
                created = True
                with warnings.catch_warnings(), zipfile.ZipFile(target, "w") as out:
                    warnings.filterwarnings("ignore", message="Duplicate name: .*", category=UserWarning)
                    for info in old.infolist():
                        if not owned(info.filename):
                            out.writestr(copy.copy(info), old.read(info))
                    for name, body in sorted(selected.items()):
                        out.writestr(zipfile.ZipInfo(name, stamp), body, compress_type=zipfile.ZIP_DEFLATED)
                    out.writestr(zipfile.ZipInfo(METADATA, stamp), json.dumps(provenance, sort_keys=True))
            with zipfile.ZipFile(output) as new:
                if new.testzip() is not None or preserved(old) != preserved(new):
                    raise ValueError("Unrelated archive entries changed")
        except BaseException:
            if created:
                output.unlink(missing_ok=True)
            raise
    return digest(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for argument in ("base", "classes", "output", "patch"):
        parser.add_argument("--" + argument, type=Path, required=True)
    args = parser.parse_args()
    print(package(args.base, args.classes, args.output, args.patch))
