"""Test execution as root."""

from pathlib import Path
from shutil import copyfile, copymode
from subprocess import run
from tempfile import mkdtemp

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
    check_privoxy_config()


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


def test_config_update(
    shell: Subprocess, privoxy_blocklist: str, privoxy_blocklist_config: str
) -> None:
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
    process = shell.run(privoxy_blocklist, "-U", "-t", "/temp/test_update")
    assert process.returncode == 0
    assert check_in(
        'TMPDIR="/temp/test_update"', Path(privoxy_blocklist_config).read_text(encoding="UTF-8")
    )
    # check FILTERS change
    process = shell.run(privoxy_blocklist, "-U", "-f", "attribute_global_contain")
    assert process.returncode == 0
    assert check_in(
        'TMPDIR="/temp/test_update"', Path(privoxy_blocklist_config).read_text(encoding="UTF-8")
    )
    assert check_in(
        "attribute_global_contain", Path(privoxy_blocklist_config).read_text(encoding="UTF-8")
    )
    # check URLS change
    process = shell.run(privoxy_blocklist, "-U", "-u", "https://test_url.update_in_config")
    assert process.returncode == 0
    assert check_in(
        '"https://test_url.update_in_config"',
        Path(privoxy_blocklist_config).read_text(encoding="UTF-8"),
    )


def test_env_based_config(shell: Subprocess, privoxy_blocklist: str, privoxy_config: str) -> None:
    """Test script run configured using environment variables only."""
    process = shell.run(privoxy_blocklist, "-C")
    assert process.returncode == int(3)
    assert check_in(
        "no URLs given. Either provide -u or set environment variable URLS.", process.stderr
    )

    process = shell.run(
        privoxy_blocklist,
        "-C",
        env=EnvironDict({"URLS": "https://foo"}),
    )
    assert process.returncode == int(3)
    assert check_in(
        "no TMPDIR given. Either provide -t or set environment variable TMPDIR.", process.stderr
    )

    process = shell.run(
        privoxy_blocklist,
        "-C",
        env=EnvironDict({"URLS": "https://foo", "TMPDIR": "/temp/blub", "DBG": "2"}),
    )
    assert process.returncode == int(4)  # return-code from wget as url is wrong
    assert check_in("URLs: https://foo", process.stdout)
    assert check_in("TMPDIR: /temp/blub", process.stdout)

    privoxy_config_test = f"{mkdtemp()}/test_config"
    if is_openwrt():
        copyfile("/etc/config/privoxy", privoxy_config_test)
    else:
        copyfile(privoxy_config, privoxy_config_test)
    process = shell.run(
        privoxy_blocklist,
        "-C",
        env=EnvironDict(
            {
                "URLS": "https://easylist-downloads.adblockplus.org/easylist.txt",
                "TMPDIR": "/temp/blub",
                "FILTERS": "class_global",
                "DBG": "2",
                "PRIVOXY_CONF": privoxy_config_test,
            }
        ),
    )
    assert process.returncode == int(0)
    assert check_in("URLs: https://easylist-downloads.adblockplus.org/easylist.txt", process.stdout)
    assert check_in("TMPDIR: /temp/blub", process.stdout)
    assert check_in("Content filters: class_global", process.stdout)
    assert check_in("Running in Activate Mode", process.stdout)
    assert check_in(
        "easylist.script.action",
        Path(privoxy_config_test).read_text(encoding="UTF-8"),
    )

    privoxy_config_dir = mkdtemp()
    privoxy_config_test = f"{privoxy_config_dir}/test_config"
    lists_dir = f"{privoxy_config_dir}/lists"
    if is_openwrt():
        copyfile("/etc/config/privoxy", privoxy_config_test)
    else:
        copyfile(privoxy_config, privoxy_config_test)
    process = shell.run(
        privoxy_blocklist,
        "-C",
        env=EnvironDict(
            {
                "URLS": "https://easylist-downloads.adblockplus.org/easylist.txt",
                "TMPDIR": "/temp/blub2",
                "FILTERS": "class_global",
                "DBG": "2",
                "PRIVOXY_CONF": privoxy_config_test,
                "LISTS_DIR": lists_dir,
            }
        ),
    )
    assert process.returncode == int(0)
    assert check_in("URLs: https://easylist-downloads.adblockplus.org/easylist.txt", process.stdout)
    assert check_in("TMPDIR: /temp/blub2", process.stdout)
    assert check_in("Content filters: class_global", process.stdout)
    assert check_in("Running in Activate Mode", process.stdout)
    assert check_in(f"Target directory for lists: {lists_dir}", process.stdout)
    assert Path(lists_dir).is_dir()
    assert Path(f"{lists_dir}/easylist.script.action").exists()
    assert Path(f"{lists_dir}/easylist.script.action").is_file()
    assert check_in(
        f"{lists_dir}/easylist.script.action",
        Path(privoxy_config_test).read_text(encoding="UTF-8"),
    )
    if is_openwrt():
        run_generate_config(shell, privoxy_config_test)
    check_privoxy_config()


def test_argument_based_config(
    shell: Subprocess, privoxy_blocklist: str, privoxy_config: str
) -> None:
    """Test update of privoxy-blocklist configuration file."""
    privoxy_config_dir = mkdtemp()
    privoxy_config_test = f"{privoxy_config_dir}/test_config"
    lists_dir = f"{privoxy_config_dir}/lists"
    if is_openwrt():
        copyfile("/etc/config/privoxy", privoxy_config_test)
    else:
        copyfile(privoxy_config, privoxy_config_test)
    process = shell.run(
        privoxy_blocklist,
        "-C",
        "-p",
        privoxy_config_test,
        "-d",
        lists_dir,
        "-v",
        "2",
        "-f",
        "class_global",
        "-t",
        "/temp/blub3",
        "-u",
        "https://easylist.to/easylist/easyprivacy.txt",
    )
    assert process.returncode == int(0)
    assert check_in("URLs: https://easylist.to/easylist/easyprivacy.txt", process.stdout)
    assert check_in("TMPDIR: /temp/blub3", process.stdout)
    assert check_in("Content filters: class_global", process.stdout)
    assert check_in("Running in Activate Mode", process.stdout)
    assert check_in(f"Target directory for lists: {lists_dir}", process.stdout)
    assert Path(lists_dir).is_dir()
    assert Path(f"{lists_dir}/easyprivacy.script.action").exists()
    assert Path(f"{lists_dir}/easyprivacy.script.action").is_file()
    assert check_in(
        f"{lists_dir}/easyprivacy.script.action",
        Path(privoxy_config_test).read_text(encoding="UTF-8"),
    )
    if is_openwrt():
        run_generate_config(shell, privoxy_config_test)
        assert check_in(
            f"{lists_dir}/easyprivacy.script.action",
            Path(privoxy_config).read_text(encoding="UTF-8"),
        )
        check_privoxy_config()
    else:
        check_privoxy_config(privoxy_config_test)


def test_convert_mode(shell: Subprocess, privoxy_blocklist: str, privoxy_config: str) -> None:
    """Test update of privoxy-blocklist configuration file."""
    privoxy_config_dir = mkdtemp()
    privoxy_config_test = f"{privoxy_config_dir}/test_config"
    lists_dir = f"{privoxy_config_dir}/lists"
    if is_openwrt():
        copyfile("/etc/config/privoxy", privoxy_config_test)
    else:
        copyfile(privoxy_config, privoxy_config_test)
    process = shell.run(
        privoxy_blocklist,
        "-A",
        "-C",
        "-p",
        privoxy_config_test,
        "-d",
        lists_dir,
        "-v",
        "2",
        "-f",
        "class_global",
        "-t",
        "/temp/blub4",
        "-u",
        "https://easylist.to/easylist/easyprivacy.txt",
    )
    assert process.returncode == int(0)
    assert check_in("URLs: https://easylist.to/easylist/easyprivacy.txt", process.stdout)
    assert check_in("TMPDIR: /temp/blub4", process.stdout)
    assert check_in("Content filters: class_global", process.stdout)
    assert check_in("Running in Convert Mode", process.stdout)
    assert check_in(f"Target directory for lists: {lists_dir}", process.stdout)
    assert check_in("Skip activation of '", process.stdout)
    assert Path(lists_dir).is_dir()
    assert Path(f"{lists_dir}/easyprivacy.script.action").exists()
    assert Path(f"{lists_dir}/easyprivacy.script.action").is_file()
    assert check_not_in(
        f"{lists_dir}/easyprivacy.script.action",
        Path(privoxy_config_test).read_text(encoding="UTF-8"),
    )
    if is_openwrt():
        run_generate_config(shell, privoxy_config_test)
        assert check_not_in(
            f"{lists_dir}/easyprivacy.script.action",
            Path(privoxy_config).read_text(encoding="UTF-8"),
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
