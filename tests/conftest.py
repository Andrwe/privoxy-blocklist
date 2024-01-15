"""define generic custom fixtures."""


import os
from pathlib import Path
from re import search
from typing import Generator, Optional

import pytest
import requests
from pytest import StashKey
from pytestshellutils.shell import Daemon

phase_report_key = StashKey[int]()


def debug_enabled() -> bool:
    """Check if debugging is enabled."""
    # RUNNER_DEBUG = set when "debug logging" activated
    # ACTIONS_RUNNER_DEBUG = set via repository variable
    # DEBUG = custom environment variable
    return (
        os.environ.get("DEBUG", None) is not None
        or os.environ.get("RUNNER_DEBUG", None) is not None
        or os.environ.get("ACTIONS_STEP_DEBUG", None) is not None
    )


def check_in(needle: str, haystack: str) -> bool:
    """Check given haystack for given string."""
    return needle in haystack


def check_not_in(needle: str, haystack: str) -> bool:
    """Check that given string is not in given text."""
    return needle not in haystack


# based on
# https://docs.pytest.org/en/latest/example/simple.html#making-test-result-information-available-in-fixtures
@pytest.hookimpl(wrapper=True, tryfirst=True)
def pytest_runtest_makereport(item: pytest.Item):
    """Capture prints of fixtures."""
    # execute all other hooks to obtain the report object
    report = yield

    if item.parent:
        # store test results for each phase ("setup", "call", "teardown") of each test
        # within module-scope
        if phase_report_key not in item.parent.stash:
            item.parent.stash.setdefault(phase_report_key, 0)
        if report.failed:
            item.parent.stash[phase_report_key] += 1

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
    if debug_enabled():
        for env in ["USER", "UID", "PWD"]:
            print(env, ":", os.environ.get(env))
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
            print(
                path,
                ":",
                oct(path_obj.stat().st_mode),
                path_obj.stat().st_uid,
                path_obj.stat().st_gid,
            )
    # privoxy must run as privoxy to suit apparmor-config on ubuntu
    run = Daemon(
        script_name="/usr/sbin/privoxy",
        base_script_args=["--no-daemon", "--user", "privoxy"],
        cwd="/etc/privoxy",
        start_timeout=10,
        check_ports=[8118],
        slow_stop=False,
    )
    run.start()
    yield run.is_running()
    run_result = run.terminate()
    logs = run_result.stdout + run_result.stderr
    # request.node is an "module" because we use the "module" scope
    node = request.node
    if (
        (phase_report_key in node.stash) and node.stash[phase_report_key] > 0
    ) or " Error: " in logs:
        print(f"\n\nprivoxy-logs\n{logs}")
    assert " Error: " not in logs


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
