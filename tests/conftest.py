"""define generic custom fixtures."""


import os
from pathlib import Path
from re import search
from typing import Dict, Generator, Optional, cast

import pytest
import requests
from pytest import CollectReport, StashKey
from pytestshellutils.shell import Daemon

phase_report_key = StashKey[Dict[str, CollectReport]]()


def debug_enabled() -> bool:
    """Check if debugging is enabled."""
    # RUNNER_DEBUG = set when "debug logging" activated
    # ACTIONS_RUNNER_DEBUG = set via repository variable
    # DEBUG = custom environment variable
    return (
        os.environ.get("DEBUG", None) is not None
        or os.environ.get("RUNNER_DEBUG", None) in [1, "1"]
        or os.environ.get("ACTIONS_RUNNER_DEBUG", None) in [True, "true"]
    )


# based on
# https://docs.pytest.org/en/latest/example/simple.html#making-test-result-information-available-in-fixtures
@pytest.hookimpl(wrapper=True, tryfirst=True)
def pytest_runtest_makereport(item: pytest.Item):
    """Capture prints of fixtures."""
    # execute all other hooks to obtain the report object
    report = yield

    if item.parent:
        if report.failed:
            # store test results for each phase ("setup", "call", "teardown") of each test
            # within module-scope
            item.parent.stash.setdefault(
                phase_report_key, cast(Dict[str, CollectReport], {})
            )[f"{report.nodeid}_{report.when}"] = report

    return report


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
def start_privoxy(request: pytest.FixtureRequest) -> Generator[bool, None, None]:
    """Test start of privoxy."""
    print("debugging: ", debug_enabled())
    if debug_enabled():
        for env in ["USER", "UID", "PWD"]:
            print(env, ": ", os.environ.get(env))
        for path in [
            "/etc/privoxy",
            "/etc/privoxy/CA",
            "/etc/privoxy/CA/certs",
            "/etc/privoxy/CA/cakey.pem",
            "/etc/privoxy/CA/cacert.crt",
        ]:
            path_obj = Path(path)
            if not path_obj.exists():
                print(path, " does not exist. ----------------")
                continue
            print(path_obj.stat().st_mode)
    run = Daemon(
        script_name="/usr/sbin/privoxy",
        base_script_args=["--no-daemon", "--user", "root"],
        cwd="/etc/privoxy",
        start_timeout=10,
        check_ports=[8118],
        slow_stop=False,
    )
    run.start()
    yield run.is_running()
    run_result = run.terminate()
    # request.node is an "module" because we use the "module" scope
    node = request.node
    if (phase_report_key in node.stash) and len(node.stash[phase_report_key]) > 0:
        print(
            f"\n\nprivoxy-results\n  stdout:\n{run_result.stdout}\n  stderr:\n{run_result.stderr}"
        )


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
        schemes.extend(["https"])
    return schemes
