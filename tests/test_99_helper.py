"""Test execution of helper script."""

from pathlib import Path
from shutil import which

from pytestshellutils.customtypes import EnvironDict
from pytestshellutils.shell import Subprocess


# must be last test as it will uninstall dependencies and check error handling
def test_missing_deps(shell: Subprocess, privoxy_blocklist: str) -> None:
    """Test error when dependency is missing."""
    if which("apk"):
        ret_pkg = shell.run("apk", "del", "privoxy")
    elif which("apt-get"):
        ret_pkg = shell.run(
            "apt-get",
            "remove",
            "--yes",
            "privoxy",
            env=EnvironDict({"DEBIAN_FRONTEND": "noninteractive"}),
        )
    elif which("opkg"):
        lock_path = Path("/var/lock")
        if not lock_path.exists():
            lock_path.mkdir()
        ret_pkg = shell.run(
            "opkg",
            "remove",
            "--force-remove",
            "--autoremove",
            "privoxy",
        )
    assert ret_pkg.returncode == 0
    ret_script = shell.run(privoxy_blocklist)
    assert ret_script.returncode == 1
    assert "Please install the package providing" in ret_script.stderr


def test_privoxy_runtime_log() -> None:
    """NOOP function to support checking privoxy logs during tear-down."""
