"""
define generic custom fixtures
"""


import os
from pathlib import Path
import pytest


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
