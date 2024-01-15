"""Test execution as root."""


from pathlib import Path
from shutil import copyfile, copymode, which

import config
import requests
from conftest import check_in, check_not_in
from urllib3.util import parse_url


def test_config_generator(shell, privoxy_blocklist) -> None:
    """Test config generator with default path."""
    config_file = Path("/etc/privoxy-blocklist.conf")
    if config_file.exists():
        config_file.unlink()
    ret = shell.run(privoxy_blocklist)
    assert ret.returncode == 2
    assert "Creating default one and exiting" in ret.stdout
    assert config_file.exists()


def test_custom_config_generator(shell, tmp_path, privoxy_blocklist) -> None:
    """Test config generator with custom path."""
    config_file = Path(f"{tmp_path}/privoxy-blocklist")
    if config_file.exists():
        config_file.unlink()
    ret = shell.run(privoxy_blocklist, "-c", str(config_file))
    assert ret.returncode == 2
    assert "Creating default one and exiting" in ret.stdout
    assert config_file.exists()


def test_version_option(shell, tmp_path, privoxy_blocklist) -> None:
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
    ret = shell.run("sed", "-i", "s/<main>/0.0.1/", str(tmp_script))
    ret = shell.run(str(tmp_script), "-V")
    assert ret.returncode == 0
    assert ret.stdout == "Version: 0.0.1\n"


def test_next_run(shell, privoxy_blocklist) -> None:
    """Test followup runs."""
    ret_script = shell.run(privoxy_blocklist)
    assert ret_script.returncode == 0
    ret_privo = shell.run(
        "/usr/sbin/privoxy", "--no-daemon", "--config-test", "/etc/privoxy/config"
    )
    assert ret_privo.returncode == 0


def test_request_success(start_privoxy, supported_schemes) -> None:
    """Test URLs not blocked by privoxy."""
    run_requests(start_privoxy, supported_schemes, config.urls_allowed, [200, 301, 302])


def test_request_block_url(start_privoxy, supported_schemes) -> None:
    """Test URLs blocked by privoxy due to easylist."""
    run_requests(start_privoxy, supported_schemes, config.urls_blocked, [403])


def test_removed_content(start_privoxy, httpserver) -> None:
    """Test filters for removing content."""
    with Path(__file__).parent.joinpath("response.html").open(
        "r", encoding="UTF-8"
    ) as f_h:
        response_html = f_h.read()
    httpserver.expect_request("/").respond_with_data(
        response_data=response_html, content_type="text/html"
    )
    parsed_url = parse_url(httpserver.url_for("/"))
    parsed_port = f":{parsed_url.port}" if parsed_url.port else ""
    scheme_less_url = f"{parsed_url.host}{parsed_port}{parsed_url.request_uri}"
    response = run_request(
        start_privoxy,
        scheme=parsed_url.scheme or "http",
        url=scheme_less_url,
        expected_code=[200],
    )
    # expected response
    assert check_in("just-some-test-string-always-present", response.text)
    for needle in config.content_removed:
        # check presence of needle without privoxy
        assert check_in(needle, requests.get(httpserver.url_for("/"), timeout=10).text)
        # check presence of needle with privoxy
        assert check_not_in(needle, response.text)
    for needle in config.content_exists:
        # check presence of needle without privoxy
        assert check_in(needle, requests.get(httpserver.url_for("/"), timeout=10).text)
        # check presence of needle with privoxy
        assert check_in(needle, response.text)


# must be second last test as it will generate unpredictable privoxy configurations
def test_predefined_custom_config_generator(shell, privoxy_blocklist) -> None:
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
def test_missing_deps(shell, privoxy_blocklist) -> None:
    """Test error when dependency is missing."""
    if which("apk"):
        ret_pkg = shell.run("apk", "del", "privoxy")
    elif which("apt-get"):
        ret_pkg = shell.run(
            "apt-get",
            "remove",
            "--yes",
            "privoxy",
            env={"DEBIAN_FRONTEND": "noninteractive"},
        )
    assert ret_pkg.returncode == 0
    ret_script = shell.run(privoxy_blocklist)
    assert ret_script.returncode == 1
    assert "Please install the package providing" in ret_script.stderr


def test_privoxy_runtime_log() -> None:
    """NOOP function to support checking privoxy logs during tear-down."""


# Heloer functions


def run_requests(
    start_privoxy, supported_schemes, urls: list[str], expected_code: list[int]
) -> None:
    """Run requests for all given urls and check for expected_code."""
    for url in urls:
        for scheme in supported_schemes:
            run_request(
                start_privoxy, scheme=scheme, url=url, expected_code=expected_code
            )


def run_request(
    start_privoxy, scheme: str, url: str, expected_code: list[int]
) -> requests.Response:
    """Run a request for given URL and return status_code."""
    assert start_privoxy
    resp = requests.get(
        f"{scheme}://{url}",
        proxies={f"{scheme}": "http://localhost:8118"},
        timeout=10,
        verify="/etc/ssl/certs/",
    )
    # run assert here to see affected URL in assertion
    assert resp.status_code in expected_code
    return resp
