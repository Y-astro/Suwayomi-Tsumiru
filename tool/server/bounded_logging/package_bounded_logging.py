#!/usr/bin/env python3
"""Overlay reviewed bounded logging class without replacing existing server fixes."""

import argparse
import copy
import hashlib
import json
from pathlib import Path
import warnings
import zipfile

BASE_SHA256 = "b42be40c310af37a6f5d9a4bdf3fd0ab57b6cfb90ce10c1ab6fc4e12d5d9c403"
UPSTREAM_COMMIT = "40bc5da57820324ed0ae724cbbc020cc4673b594"
OWNERS = (
    "xyz/nulldev/ts/config/LoggingKt",
)
METADATA = "META-INF/tsumiru-bounded-logging.json"


def digest(path):
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def owned(name):
    return name.endswith(".class") and any(
        name == owner + ".class" or name.startswith(owner + "$") for owner in OWNERS
    )


def preserved(archive):
    return [
        (info.filename, info.external_attr, hashlib.sha256(archive.read(info)).hexdigest())
        for info in archive.infolist()
        if not owned(info.filename) and info.filename != METADATA
    ]


def package(base, classes, output, patch, expected_sha=BASE_SHA256):
    base, classes, output = Path(base), Path(classes), Path(output)
    if digest(base) != expected_sha:
        raise ValueError("Base JAR differs from the reviewed installed build: " + digest(base))
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
            raise ValueError("Bounded logging patch already installed")
        if any(names.count(name) != 1 for name in names if owned(name)):
            raise ValueError("Ambiguous original class")
        provenance = {
            "format": 1,
            "base_jar_sha256": expected_sha,
            "upstream_commit": UPSTREAM_COMMIT,
            "source_patch_sha256": digest(patch),
            "class_sha256": {name: hashlib.sha256(body).hexdigest() for name, body in sorted(selected.items())},
        }
        stamp = old.getinfo(OWNERS[0] + ".class").date_time
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
    parser.add_argument("base", help="Base JAR file path")
    parser.add_argument("classes", help="Compiled classes directory")
    parser.add_argument("output", help="Output JAR destination")
    parser.add_argument("patch", help="Source patch file")
    args = parser.parse_args()
    result = package(args.base, args.classes, args.output, args.patch)
    print("Packaged candidate JAR SHA256:", result)
