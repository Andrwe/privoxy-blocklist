"""Test execution as root."""


from pathlib import Path
from shutil import which
from tempfile import gettempdir

import requests


def test_missing_deps(shell, privoxy_blocklist) -> None:
    """Test error when dependency is missing."""
    if which("apk"):
        ret_pkg = shell.run("apk", "del", "privoxy")
    elif which("apt-get"):
        ret_pkg = shell.run(
            "sudo",
            "apt-get",
            "remove",
            "--yes",
            "privoxy",
            env={"DEBIAN_FRONTEND": "noninteractive"},
        )
    assert ret_pkg.returncode == 0
    ret_script = shell.run("sudo", privoxy_blocklist)
    assert ret_script.returncode == 1
    assert "Please install the package providing" in ret_script.stderr
    ret_install = shell.run("sudo", str(Path("helper/install_deps.sh").absolute()))
    assert ret_install.returncode == 0


def test_config_generator(shell, privoxy_blocklist) -> None:
    """Test config generator with default path."""
    config = Path("/etc/privoxy-blocklist.conf")
    if config.exists():
        config.unlink()
    ret = shell.run("sudo", privoxy_blocklist)
    assert ret.returncode == 1
    assert "Creating default one and exiting" in ret.stdout
    assert config.exists()


def test_custom_config_generator(shell, privoxy_blocklist) -> None:
    """Test config generator with custom path."""
    config = Path(f"{gettempdir()}/privoxy-blocklist")
    if config.exists():
        config.unlink()
    ret = shell.run("sudo", privoxy_blocklist, "-c", str(config))
    assert ret.returncode == 1
    assert "Creating default one and exiting" in ret.stdout
    assert config.exists()


def test_next_run(shell, privoxy_blocklist) -> None:
    """Test followup runs."""
    ret_script = shell.run("sudo", privoxy_blocklist)
    assert ret_script.returncode == 0
    ret_privo = shell.run(
        "/usr/sbin/privoxy", "--no-daemon", "--config-test", "/etc/privoxy/config"
    )
    assert ret_privo.returncode == 0


def test_request_success(start_privoxy, supported_schemes) -> None:
    """Test URLs not blocked by privoxy."""
    urls = ["duckduckgo.com/", "hs-exp.jp/ads/"]
    run_requests(start_privoxy, supported_schemes, urls, [200, 301, 302])


def test_request_block_url(start_privoxy, supported_schemes) -> None:
    """Test URLs blocked by privoxy due to easylist."""
    urls = ["andrwe.org/ads/", "andrwe.jp/ads/", "pubfeed.linkby.com"]
    run_requests(start_privoxy, supported_schemes, urls, [403])


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
    )
    # run assert here to see affected URL in assertion
    assert resp.status_code in expected_code
    return resp
