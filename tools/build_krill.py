#!/usr/bin/env python3
"""Fetch Krill loader v194 into a temp dir, build for Wolf64, copy PRGs into krill/.

Source is not vendored. Regular build.bat only consumes krill/loader.prg and
krill/install.prg. Re-run this when INSTALL/RESIDENT/ZP or loaderconfig.inc change.

Needs GNU make, perl, and ca65. On Windows, Git's perl is used; make and cc65
are downloaded into the temp tree if they are not on PATH.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Optional
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent
KRILL_OUT = ROOT / "krill"
CONFIG_DIR = KRILL_OUT / "config"

KRILL_ZIP_URL = "https://csdb.dk/getinternalfile.php/238373/loader-v194.zip"
CC65_ZIP_URL = "https://downloads.sourceforge.net/project/cc65/cc65-snapshot-win32.zip"
MAKE_ZIP_URL = (
	"https://downloads.sourceforge.net/project/ezwinports/"
	"make-4.4.1-without-guile-w32-bin.zip"
)

INSTALL = "2000"
RESIDENT = "4e00"
ZP = "60"

UA = "Wolf64-build_krill/1.0"


def download(url: str, dest: Path) -> None:
	print(f"  GET {url}")
	req = Request(url, headers={"User-Agent": UA})
	with urlopen(req, timeout=120) as r:
		dest.write_bytes(r.read())
	print(f"  wrote {dest} ({dest.stat().st_size} bytes)")


def find_git_bash() -> Optional[Path]:
	p = Path(r"C:\Program Files\Git\bin\bash.exe")
	return p if p.is_file() else None


def find_perl() -> Optional[Path]:
	w = shutil.which("perl")
	if w:
		return Path(w)
	p = Path(r"C:\Program Files\Git\usr\bin\perl.exe")
	return p if p.is_file() else None


def posix_path(p: Path) -> str:
	s = str(p.resolve()).replace("\\", "/")
	if len(s) >= 2 and s[1] == ":":
		return "/" + s[0].lower() + s[2:]
	return s


def main() -> None:
	if not (CONFIG_DIR / "loaderconfig.inc").is_file():
		print(f"missing {CONFIG_DIR / 'loaderconfig.inc'}", file=sys.stderr)
		sys.exit(1)

	perl = find_perl()
	if perl is None:
		print("perl not found (Git for Windows usr\\bin\\perl.exe is fine)", file=sys.stderr)
		sys.exit(1)

	bash = find_git_bash()
	ca65 = shutil.which("ca65")
	make = shutil.which("make")
	if make and Path(make).resolve().name.lower() in ("make.bat", "make.cmd"):
		make = None

	with tempfile.TemporaryDirectory(prefix="w64_krill_") as tmp:
		tmp_dir = Path(tmp)
		zip_path = tmp_dir / "loader-v194.zip"
		download(KRILL_ZIP_URL, zip_path)
		with zipfile.ZipFile(zip_path) as z:
			z.extractall(tmp_dir)

		src = tmp_dir / "loader" / "src"
		if not (src / "Makefile").is_file():
			print(f"no loader/src/Makefile in zip (saw {list(tmp_dir.iterdir())})", file=sys.stderr)
			sys.exit(1)

		tools = tmp_dir / "tools"
		tools.mkdir()
		env_path_parts = [str(tools)]

		if ca65 is None:
			cc65_zip = tmp_dir / "cc65.zip"
			download(CC65_ZIP_URL, cc65_zip)
			with zipfile.ZipFile(cc65_zip) as z:
				z.extractall(tools / "cc65")
			# snapshot unpacks as cc65/bin/ca65.exe or bin/ca65.exe
			found = list((tools / "cc65").rglob("ca65.exe"))
			if not found:
				found = list((tools / "cc65").rglob("ca65"))
			if not found:
				print("ca65 not in cc65 zip", file=sys.stderr)
				sys.exit(1)
			env_path_parts.insert(0, str(found[0].parent))
			print(f"  ca65: {found[0]}")
		else:
			print(f"  ca65: {ca65}")

		if make is None:
			make_zip = tmp_dir / "make.zip"
			download(MAKE_ZIP_URL, make_zip)
			with zipfile.ZipFile(make_zip) as z:
				z.extractall(tools / "make")
			found_make = list((tools / "make").rglob("make.exe"))
			if not found_make:
				print("make.exe not in ezwinports zip", file=sys.stderr)
				sys.exit(1)
			env_path_parts.insert(0, str(found_make[0].parent))
			print(f"  make: {found_make[0]}")
		else:
			print(f"  make: {make}")
			env_path_parts.append(str(Path(make).parent))

		env_path_parts.append(str(perl.parent))
		if ca65:
			env_path_parts.append(str(Path(ca65).parent))

		extconfig = posix_path(CONFIG_DIR)
		src_posix = posix_path(src)
		path_posix = ":".join(posix_path(Path(p)) for p in env_path_parts)

		cmd_inner = (
			f'export PATH="{path_posix}:$PATH"; '
			f'cd "{src_posix}" && '
			f"make PLATFORM=c64 prg INSTALL={INSTALL} RESIDENT={RESIDENT} ZP={ZP} "
			f'EXTCONFIGPATH="{extconfig}"'
		)

		if bash is not None:
			cmd = [str(bash), "-lc", cmd_inner]
		else:
			cmd = [
				"make",
				"-C",
				str(src),
				"PLATFORM=c64",
				"prg",
				f"INSTALL={INSTALL}",
				f"RESIDENT={RESIDENT}",
				f"ZP={ZP}",
				f"EXTCONFIGPATH={CONFIG_DIR}",
			]

		print("  ", " ".join(cmd))
		env = os.environ.copy()
		env["PATH"] = os.pathsep.join(env_path_parts + [env.get("PATH", "")])
		subprocess.check_call(cmd, env=env)

		build = tmp_dir / "loader" / "build"
		loader_src = build / "loader-c64.prg"
		install_src = build / "install-c64.prg"
		syms_src = build / "loadersymbols-c64.inc"
		for p in (loader_src, install_src, syms_src):
			if not p.is_file():
				print(f"missing build output: {p}", file=sys.stderr)
				sys.exit(1)

		KRILL_OUT.mkdir(exist_ok=True)
		shutil.copy2(loader_src, KRILL_OUT / "loader.prg")
		shutil.copy2(install_src, KRILL_OUT / "install.prg")
		shutil.copy2(syms_src, KRILL_OUT / "loadersymbols-c64.inc")
		print(f"copied loader.prg install.prg loadersymbols-c64.inc -> {KRILL_OUT}")


if __name__ == "__main__":
	main()
