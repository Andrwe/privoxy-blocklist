"""Test execution as root."""

from pathlib import Path
from shutil import copyfile, copymode, which
from subprocess import run

import requests
from pytestshellutils.customtypes import EnvironDict
from pytestshellutils.shell import Subprocess

import config
from conftest import check_in, check_not_in, check_privoxy_config, is_openwrt, run_generate_config


def test_config_generator(
    shell: Subprocess,
    privoxy_blocklist: str,
    privoxy_blocklist_config: str,
) -> None:
    """Test config generator with default path."""
    config_file = Path(privoxy_blocklist_config)
    if config_file.exists():
        config_file.unlink()
    ret = shell.run(privoxy_blocklist)
    assert ret.returncode == int(2)
    assert "Creating default one and exiting" in ret.stdout
    assert config_file.exists()


def test_custom_config_generator(
    shell: Subprocess,
    tmp_path: str,
    privoxy_blocklist: str,
) -> None:
    """Test config generator with custom path."""
    config_file = Path(f"{tmp_path}/privoxy-blocklist")
    if config_file.exists():
        config_file.unlink()
    ret = shell.run(privoxy_blocklist, "-c", str(config_file))
    assert ret.returncode == int(2)
    assert "Creating default one and exiting" in ret.stdout
    assert config_file.exists()


def test_version_option(
    shell: Subprocess,
    tmp_path: str,
    privoxy_blocklist: str,
) -> None:
    """Test version option."""
    ret = shell.run(privoxy_blocklist, "-V")
    assert ret.returncode == 0
    assert ret.stdout == "Version: <main>\n"
    tmp_script = Path(f"{tmp_path}/privoxy-blocklist.sh")
    if tmp_script.exists():
        tmp_script.unlink()
    cur_script = Path(privoxy_blocklist)
    copyfile(cur_script, tmp_script)
    copymode(cur_script, tmp_script)
    shell.run("sed", "-i", "s/<main>/0.0.1/", str(tmp_script))
    ret = shell.run(str(tmp_script), "-V")
    assert ret.returncode == 0
    assert ret.stdout == "Version: 0.0.1\n"


def test_filter_check(shell: Subprocess, privoxy_blocklist: str) -> None:
    """Test filtertype check."""
    cmd = [privoxy_blocklist, "-f", "bla"]
    ret_script = shell.run(*cmd)
    assert ret_script.returncode == 1
    assert ret_script.stdout == ""
    assert "Unknown filters: bla" in ret_script.stderr.strip()


def test_next_run(
    shell: Subprocess,
    privoxy_blocklist: str,
    filtertypes: list[str],
) -> None:
    """Test followup runs."""
    cmd = [privoxy_blocklist]
    for filtertype in filtertypes:
        cmd.extend(["-f", filtertype])
    ret_script = shell.run(*cmd)
    assert ret_script.returncode == 0
    ret_privo = check_privoxy_config()
    assert ret_privo.returncode == 0


def test_request_success(start_privoxy, supported_schemes) -> None:
    """Test URLs not blocked by privoxy."""
    run_requests(start_privoxy, supported_schemes, config.urls_allowed, [200, 301, 302])


def test_request_block_url(start_privoxy, supported_schemes) -> None:
    """Test URLs blocked by privoxy due to easylist."""
    run_requests(start_privoxy, supported_schemes, config.urls_blocked, [403])


def test_content_removed(start_privoxy, webserver) -> None:
    """Test filters for removing content."""
    response = run_request(
        start_privoxy,
        scheme=webserver.scheme,
        url=webserver.scheme_less_url,
        expected_code=[200],
    )
    # expected response
    assert check_in("just-some-test-string-always-present", response.text)
    for needle in config.content_removed:
        # check presence of needle without privoxy
        assert check_in(needle, requests.get(webserver.origin_url, timeout=10).text)
        # check presence of needle with privoxy
        assert check_not_in(needle, response.text)


def test_content_exists(start_privoxy, webserver) -> None:
    """Test filters for removing content."""
    response = run_request(
        start_privoxy,
        scheme=webserver.scheme,
        url=webserver.scheme_less_url,
        expected_code=[200],
    )
    # expected response
    assert check_in("just-some-test-string-always-present", response.text)
    for needle in config.content_exists:
        # check presence of needle without privoxy
        assert check_in(needle, requests.get(webserver.origin_url, timeout=10).text)
        # check presence of needle with privoxy
        assert check_in(needle, response.text)


def test_remove(privoxy_blocklist: str, privoxy_config: str, shell: Subprocess) -> None:
    """Run tests for removal of privoxy-blocklist configs."""
    process = run(
        [privoxy_blocklist, "-r"],
        capture_output=True,
        input="n\n",
        text=True,
        check=True,
    )
    assert process.returncode == 0
    assert check_in("script.action", Path(privoxy_config).read_text(encoding="UTF-8"))
    assert check_in("script.filter", Path(privoxy_config).read_text(encoding="UTF-8"))
    process = run(
        [privoxy_blocklist, "-r"],
        capture_output=True,
        input="y\n",
        text=True,
        check=True,
    )
    assert process.returncode == 0
    assert check_in("Lists removed.", process.stdout)
    if is_openwrt():
        assert check_not_in(
            "script.action",
            Path("/etc/config/privoxy").read_text(encoding="UTF-8"),
        )
        assert check_not_in(
            "script.filter",
            Path("/etc/config/privoxy").read_text(encoding="UTF-8"),
        )
        # required to regenerate privoxy config on openwrt
        run_generate_config(shell)
    assert check_not_in(
        "script.action",
        Path(privoxy_config).read_text(encoding="UTF-8"),
    )
    assert check_not_in(
        "script.filter",
        Path(privoxy_config).read_text(encoding="UTF-8"),
    )


def test_config_update(privoxy_blocklist: str, privoxy_blocklist_config: str) -> None:
    """Test update of privoxy-blocklist configuration file."""
    assert check_not_in(
        'TMPDIR="/temp/test_update"', Path(privoxy_blocklist_config).read_text(encoding="UTF-8")
    )
    assert check_not_in(
        "attribute_global_contain", Path(privoxy_blocklist_config).read_text(encoding="UTF-8")
    )
    assert check_not_in(
        '"https://test_url.update_in_config"',
        Path(privoxy_blocklist_config).read_text(encoding="UTF-8"),
    )
    # check TMPDIR change
    process = run(
        [privoxy_blocklist, "-U", "-t", "/temp/test_update"],
        capture_output=True,
        input="y\n",
        text=True,
        check=True,
    )
    assert process.returncode == 0
    assert check_in(
        'TMPDIR="/temp/test_update"', Path(privoxy_blocklist_config).read_text(encoding="UTF-8")
    )
    # check FILTERS change
    process = run(
        [privoxy_blocklist, "-U", "-f", "attribute_global_contain"],
        capture_output=True,
        input="y\n",
        text=True,
        check=True,
    )
    assert process.returncode == 0
    assert check_in(
        'TMPDIR="/temp/test_update"', Path(privoxy_blocklist_config).read_text(encoding="UTF-8")
    )
    assert check_in(
        "attribute_global_contain", Path(privoxy_blocklist_config).read_text(encoding="UTF-8")
    )
    # check URLS change
    process = run(
        [privoxy_blocklist, "-U", "-u", "https://test_url.update_in_config"],
        capture_output=True,
        input="y\n",
        text=True,
        check=True,
    )
    assert process.returncode == 0
    assert check_in(
        '"https://test_url.update_in_config"',
        Path(privoxy_blocklist_config).read_text(encoding="UTF-8"),
    )


# must be second last test as it will generate unpredictable privoxy configurations
def test_predefined_custom_config_generator(
    shell: Subprocess,
    privoxy_blocklist: str,
) -> None:
    """Run tests for all pre-defined configs."""
    test_config_dir = Path(__file__).parent / "configs"
    for config_file in test_config_dir.iterdir():
        if not config_file.is_file():
            continue
        ret = shell.run(privoxy_blocklist, "-c", str(config_file))
        assert ret.returncode == 0
        assert check_not_in("Creating default one and exiting", ret.stdout)
        for check in config.config_checks.get(config_file.name, []):
            assert check[0](check[1], ret.stdout)
        assert config_file.exists()


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


# Heloer functions


def run_requests(
    start_privoxy,
    supported_schemes,
    urls: list[str],
    expected_code: list[int],
) -> None:
    """Run requests for all given urls and check for expected_code."""
    for url in urls:
        for scheme in supported_schemes:
            run_request(
                start_privoxy,
                scheme=scheme,
                url=url,
                expected_code=expected_code,
            )


def run_request(
    start_privoxy,
    scheme: str,
    url: str,
    expected_code: list[int],
) -> requests.Response:
    """Run a request for given URL and return status_code."""
    assert start_privoxy
    resp = requests.get(
        f"{scheme}://{url}",
        proxies={f"{scheme}": "http://localhost:8118"},
        timeout=10,
        verify="/etc/ssl/certs/",
        allow_redirects=False,
    )
    # run assert here to see affected URL in assertion
    assert resp.status_code in expected_code
    return resp
