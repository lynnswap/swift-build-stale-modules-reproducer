from pathlib import Path
import hashlib
import json
import shutil
import sqlite3
import sys

root = Path(sys.argv[1])
output = Path(sys.argv[2])
phase = sys.argv[3]
logs = output / "logs"
products = output / "DerivedData/Build/Products"
files = []
for path in sorted(products.rglob("*")):
    if path.is_file() and ("Foo.swiftmodule" in str(path) or path.name == "Consumer"):
        stat = path.stat()
        files.append({"path": str(path.relative_to(output)), "size": stat.st_size,
                      "mtime_ns": stat.st_mtime_ns,
                      "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
(logs / f"phase{phase}-products.json").write_text(json.dumps(files, indent=2) + "\n")
for relative in ["Package.swift", "Sources/Consumer/main.swift", "FooPackage/Package.swift",
                 "FooPackage/Sources/Foo/Foo.swift", "FooPackage/Sources/A/A.swift",
                 "FooPackage/Sources/B/B.swift"]:
    destination = logs / f"phase{phase}-sources" / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / relative, destination)
database = output / "DerivedData/Build/Intermediates.noindex/XCBuildData/build.db"
if database.exists():
    with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as source:
        with sqlite3.connect(logs / f"phase{phase}-build.db") as destination:
            source.backup(destination)
