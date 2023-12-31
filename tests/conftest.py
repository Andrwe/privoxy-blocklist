"""define generic custom fixtures."""


import os
from pathlib import Path
from re import search
from typing import Generator, Optional

import pytest
import requests
from pytestshellutils.shell import Daemon


@pytest.fixture(scope="module")
def privoxy_blocklist() -> str:
    """Return the path to privoxy-blocklist.sh."""
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
def start_privoxy() -> Generator[bool, None, None]:
    """Test start of privoxy."""
    run = Daemon(
        script_name="/usr/sbin/privoxy",
        base_script_args=["--no-daemon"],
        cwd="/etc/privoxy",
        start_timeout=10,
        check_ports=[8118],
    )
    run.start()
    yield run.is_running()
    run.terminate()


@pytest.fixture(scope="module")
# pylint: disable=redefined-outer-name # reusing fixture
def check_https_inspection(start_privoxy) -> Optional[bool]:
    """Test if https inspection is enabled."""
    if not start_privoxy:
        return None
    resp = requests.get(
        "http://config.privoxy.org/show-status",
        proxies={"http": "http://localhost:8118"},
        timeout=10,
    )
    check_support = search(
        r"<code>FEATURE_HTTPS_INSPECTION</code>.*\n\s*<td>\s*No\s*</", resp.text
    )
    if check_support:
        return False
    return True


@pytest.fixture(scope="module")
# pylint: disable=redefined-outer-name # reusing fixture
def supported_schemes(check_https_inspection) -> list[str]:
    """Return support schemes (HTTP, HTTPS) based on privoxy build specs."""
    schemes = ["http"]
    if check_https_inspection:
        schemes.extend("https")
    return schemes
