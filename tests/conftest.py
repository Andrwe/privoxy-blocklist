"""
define generic custom fixtures
"""


import os
from pathlib import Path
import pytest
import pytestshellutils


@pytest.fixture
def privoxy_blocklist():
    """return the path to privoxy-blocklist.sh"""
    for known_path in [
        "./privoxy-blocklist.sh",
        "/privoxy-blocklist.sh",
        "/app/privoxy-blocklist.sh",
    ]:
        path = Path(known_path)
        if path.exists() and path.is_file() and os.access(path, os.X_OK):
            return str(path.absolute())
    raise FileNotFoundError("Could not find privoxy-blocklist.sh")


@pytest.fixture(scope="module")
def start_privoxy(shell):
    """test start of privoxy"""
    if shell.run("pgrep", "-f", "/usr/sbin/privoxy").returncode == 0:
        yield True
        return
    run = pytestshellutils.shell.Daemon(
        script_name="/usr/sbin/privoxy",
        base_script_args=["--no-daemon"],
        cwd="/etc/privoxy",
        start_timeout=10,
        check_ports=[8118],
    )
    run.start()
    if not run.is_running():
        return False
    if not shell.run("pgrep", "-f", "/usr/sbin/privoxy").returncode == 0:
        return False
    yield run.is_running()
    run.terminate()
