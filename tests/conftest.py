"""define generic custom fixtures."""

import os
from pathlib import Path
from re import search
from shutil import copyfile, which
from subprocess import run
from tempfile import mkdtemp
from typing import Generator, Optional

import pytest
import requests
from pytestshellutils.shell import Daemon, Subprocess
from urllib3.util import Url, parse_url

phase_report_key = pytest.StashKey[int]()


class UrlParsed:
    """Class to parse and store URL."""

    origin_url: str
    parsed_url: Url
    scheme: str
    scheme_less_url: str

    def __init__(self, url: str):
        """Initialize object by parsing given URL."""
        self.origin_url = url
        self.parsed_url = parse_url(self.origin_url)
        self.scheme = self.parsed_url.scheme or "http"
        parsed_port = f":{self.parsed_url.port}" if self.parsed_url.port else ""
        self.scheme_less_url = f"{self.parsed_url.host}{parsed_port}{self.parsed_url.request_uri}"


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


def is_apparmor() -> bool:
    """Check if current OS has apparmor enabled."""
    aa_exec = which("aa-status")
    if not aa_exec:
        return False
    return run(aa_exec or "/usr/sbin/aa-status", check=False, capture_output=True).returncode == 0


def is_openwrt() -> bool:
    """Check if current OS is OpenWRT based."""
    os_release_file = Path("/etc/os-release")
    if not os_release_file.exists():
        return False
    os_release_content = os_release_file.read_text(encoding="UTF-8")
    return search(r'ID_LIKE=".*(?<="|\s)openwrt(?="|\s).*"', os_release_content) is not None


def check_in(needle: str, haystack: str) -> bool:
    """Check given haystack for given string."""
    return needle in haystack


def check_not_in(needle: str, haystack: str) -> bool:
    """Check that given string is not in given text."""
    return needle not in haystack


def run_generate_config(shell: Subprocess, config_path: str = "") -> None:
    """Generate Privoxy config on OpenWRT."""
    script_path = f"{mkdtemp()}/generate_config.sh"
    Path(script_path).write_text(
        "source $IPKG_INSTROOT/lib/functions.sh; source /etc/rc.d/K10privoxy; _uci2conf",
        encoding="UTF-8",
    )
    if config_path:
        orig_path = "/etc/config/privoxy"
        copyfile(orig_path, f"{orig_path}_bak")
        copyfile(config_path, orig_path)
    generate_run = shell.run("/bin/ash", script_path)
    if config_path:
        copyfile(f"{orig_path}_bak", orig_path)
        Path(f"{orig_path}_bak").unlink(missing_ok=True)
    assert generate_run.returncode == 0


def _get_privoxy_config(shell: Subprocess) -> str:
    """Return path to privoxy config file."""
    config_path = "/etc/privoxy/config"
    if is_openwrt():
        config_path = "/var/etc/privoxy.conf"
        run_generate_config(shell)
    assert Path(config_path).exists()
    return config_path


def _get_privoxy_args(shell: Subprocess, config_path: str = "") -> list[str]:
    """Return arguments for running Privoxy."""
    privoxy_args = ["--no-daemon", "--user", "privoxy"]
    if config_path:
        privoxy_args.append(config_path)
        if is_apparmor():
            config_dir = str(Path(config_path).parent)
            data = Path("/etc/apparmor.d/usr.sbin.privoxy").read_text(encoding="UTF-8")
            if config_dir not in data:
                data = f"""
                    include if exists <tunables>
                    /usr/sbin/privoxy {"{"}
                      #include <abstractions/base>
                      #include <abstractions/nameservice>
                      capability setgid,
                      capability setuid,
                      /usr/sbin/privoxy mr,
                      /etc/privoxy/** r,
                      {config_dir}/** r,
                      owner /etc/privoxy/match-all.action rw,
                      owner /etc/privoxy/user.action rw,
                      /run/privoxy*.pid rw,
                      /usr/share/doc/privoxy/user-manual/** r,
                      /usr/share/doc/privoxy/p_doc.css r,
                      owner /var/lib/privoxy/** rw,
                      owner /var/log/privoxy/logfile rw,
                    {"}"}
                    """
                Path("/etc/apparmor.d/usr.sbin.privoxy").write_text(data, encoding="UTF-8")
                apparmor = shell.run("apparmor_parser", "-r", "/etc/apparmor.d/usr.sbin.privoxy")
                assert apparmor.returncode == 0
    else:
        privoxy_args.append(_get_privoxy_config(shell))
    return privoxy_args


def check_privoxy_config(config_path: str = "") -> None:
    """Test start of privoxy."""
    # not using shell-fixture to simplify call of this function
    shell = Subprocess()
    command = ["/usr/sbin/privoxy", "--config-test"]
    command.extend(_get_privoxy_args(shell, config_path))
    ret_privo = shell.run(*command)
    assert ret_privo.returncode == 0
    assert check_not_in(" Error: ", ret_privo.stdout + ret_privo.stderr)
    assert check_not_in(" error: ", ret_privo.stdout + ret_privo.stderr)


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
def privoxy_config(shell: Subprocess) -> str:
    """Fixture to return arguments for running Privoxy."""
    return _get_privoxy_config(shell)


@pytest.fixture(scope="module")
def get_privoxy_args(shell: Subprocess) -> list[str]:
    """Fixture to return arguments for running Privoxy."""
    return _get_privoxy_args(shell)


@pytest.fixture()
def webserver(httpserver) -> UrlParsed:
    """Start HTTP server and return parsed URL object."""
    with Path(__file__).parent.joinpath("response.html").open(
        "r",
        encoding="UTF-8",
    ) as f_h:
        response_html = f_h.read()
    httpserver.expect_request("/").respond_with_data(
        response_data=response_html,
        content_type="text/html",
    )
    return UrlParsed(httpserver.url_for("/"))


@pytest.fixture(scope="module")
def filtertypes() -> list[str]:
    """Return filtertypes supported by privoxy-blocklist."""
    filter_types = []
    with Path(__file__).parent.parent.joinpath("privoxy-blocklist.sh").open(
        "r",
        encoding="UTF-8",
    ) as f_h:
        found_line = False
        for line in f_h.readlines():
            if not found_line and not line.startswith("FILTERTYPES"):
                continue
            if line.startswith("FILTERTYPES"):
                found_line = True
                continue
            if line.endswith(")\n"):
                break
            filter_types.append(line.strip().strip('"'))
    return filter_types


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
def privoxy_blocklist_config() -> str:
    """Return the path to privoxy-blocklist.conf."""
    config_path = "/etc/privoxy-blocklist.conf"
    if os.uname().sysname == "Darwin":
        config_path = "/usr/local/etc/privoxy-blocklist.conf"
    if is_openwrt():
        config_path = "/etc/config/privoxy-blocklist.conf"
    return config_path


@pytest.fixture(scope="module")
def start_privoxy(
    request: pytest.FixtureRequest,
    get_privoxy_args: list[str],
) -> Generator[bool, None, None]:
    """Test start of privoxy."""
    # privoxy must run as privoxy to suit apparmor-config on ubuntu
    run = Daemon(
        script_name="/usr/sbin/privoxy",
        base_script_args=get_privoxy_args,
        cwd="/etc/privoxy",
        start_timeout=10,
        check_ports=[8118],
        slow_stop=False,
    )
    run.start()
    yield run.is_running()
    # empty ports list as psutil.process_iter() does not support "connections" anymore
    run.listen_ports = []
    run.check_ports = []
    run_result = run.terminate()
    logs = run_result.stdout + run_result.stderr
    # request.node is an "module" because we use the "module" scope
    node = request.node
    if (
        (phase_report_key in node.stash) and node.stash[phase_report_key] > 0
    ) or " Error: " in logs:
        print(f"\n\nprivoxy-logs\n{logs}")  # noqa: T201
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
        r"<code>FEATURE_HTTPS_INSPECTION</code>.*\n\s*<td>\s*No\s*</",
        resp.text,
    )
    return not check_support


@pytest.fixture(scope="module")
# pylint: disable=redefined-outer-name # reusing fixture
def supported_schemes(check_https_inspection) -> list[str]:
    """Return support schemes (HTTP, HTTPS) based on privoxy build specs."""
    schemes = ["http"]
    if check_https_inspection:
        schemes.extend(["https"])
    return schemes
