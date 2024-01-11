"""Test execution as root."""


from pathlib import Path
from shutil import copyfile, copymode, which

import requests


def test_config_generator(shell, privoxy_blocklist) -> None:
    """Test config generator with default path."""
    config = Path("/etc/privoxy-blocklist.conf")
    if config.exists():
        config.unlink()
    ret = shell.run(privoxy_blocklist)
    assert ret.returncode == 2
    assert "Creating default one and exiting" in ret.stdout
    assert config.exists()


def test_custom_config_generator(shell, tmp_path, privoxy_blocklist) -> None:
    """Test config generator with custom path."""
    config = Path(f"{tmp_path}/privoxy-blocklist")
    if config.exists():
        config.unlink()
    ret = shell.run(privoxy_blocklist, "-c", str(config))
    assert ret.returncode == 2
    assert "Creating default one and exiting" in ret.stdout
    assert config.exists()


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
    # FIXME: see https://github.com/Andrwe/privoxy-blocklist/issues/35
    urls = ["duckduckgo.com/", "hs-exp.jp/ads/"]
    urls = ["duckduckgo.com/"]
    run_requests(start_privoxy, supported_schemes, urls, [200, 301, 302])


def test_request_block_url(start_privoxy, supported_schemes) -> None:
    """Test URLs blocked by privoxy due to easylist."""
    urls = [
        "andrwe.org/ads/",
        "andrwe.jp/ads/",
        "pubfeed.linkby.com",
        f"s3.{'a'*6}.amazonaws.com/{'0123abcd'*6}/{'ab,12'*2}/",
    ]
    urls = ["andrwe.org/ads/", "andrwe.jp/ads/", "pubfeed.linkby.com"]
    run_requests(start_privoxy, supported_schemes, urls, [403])


def test_predefined_custom_config_generator(shell, privoxy_blocklist) -> None:
    """Run tests for all pre-defined configs."""
    checks = {
        "url_extended_config.conf": [
            (
                check_in,
                "Processing https://raw.githubusercontent.com/easylist/easylist/master/"
                "easylist/easylist_allowlist_general_hide.txt",
            ),
            (
                check_in,
                "Processing https://easylist-downloads.adblockplus.org/easylistgermany.txt",
            ),
            (
                check_in,
                "The list recieved from https://raw.githubusercontent.com/easylist/easylist/master"
                "/easylist/easylist_allowlist_general_hide.txt does not contain AdblockPlus list "
                "header. Try to process anyway.",
            ),
            (
                check_not_in,
                "created and added image handler",
            ),
        ],
        "debugging.conf": [
            (
                check_in,
                "Processing https://easylist-downloads.adblockplus.org/easylistgermany.txt",
            ),
            (
                check_not_in,
                "does not contain AdblockPlus list header.",
            ),
            (
                check_in,
                "‘/tmp/privoxy-blocklist.sh/easylist.txt’ saved",
            ),
            (
                check_in,
                "created and added image handler",
            ),
        ],
    }
    test_config_dir = Path(__file__).parent / "configs"
    for config in test_config_dir.iterdir():
        if not config.is_file():
            continue
        ret = shell.run(privoxy_blocklist, "-c", str(config))
        assert ret.returncode == 0
        assert check_not_in("Creating default one and exiting", ret.stdout)
        for check in checks.get(config.name, []):
            assert check[0](check[1], ret.stdout)
        assert config.exists()


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


def check_in(needle: str, haystack: str) -> bool:
    """Check given haystack for given string."""
    return needle in haystack


def check_not_in(needle: str, haystack: str) -> bool:
    """Check that given string is not in given text."""
    return needle not in haystack


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
