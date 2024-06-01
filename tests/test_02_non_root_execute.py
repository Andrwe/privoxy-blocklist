"""Test execution as non-root."""

from pathlib import Path
from shutil import chown, copyfile, copymode
from subprocess import run
from tempfile import mkdtemp

from pytestshellutils.shell import Subprocess

from conftest import check_in, check_not_in, is_openwrt, run_generate_config


def test_convert_mode(shell: Subprocess, privoxy_blocklist: str, privoxy_config: str) -> None:
    """Test update of privoxy-blocklist configuration file."""
    privoxy_config_dir = mkdtemp()
    privoxy_config_test = f"{privoxy_config_dir}/test_config"
    privoxy_blocklist_test = f"{privoxy_config_dir}/{privoxy_blocklist.split('/')[-1]}"
    lists_dir = f"{privoxy_config_dir}/lists"
    converted_dir = mkdtemp()
    chown(privoxy_config_dir, user="ci_test_user")
    chown(converted_dir, user="ci_test_user")
    if is_openwrt():
        copyfile("/etc/config/privoxy", privoxy_config_test)
    else:
        copyfile(privoxy_config, privoxy_config_test)
    copyfile(privoxy_blocklist, privoxy_blocklist_test)
    copymode(privoxy_blocklist, privoxy_blocklist_test)
    chown(privoxy_blocklist_test, user="ci_test_user")
    process = run(
        [
            privoxy_blocklist_test,
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
            converted_dir,
            "-u",
            "https://easylist.to/easylist/easyprivacy.txt",
        ],
        user="ci_test_user",
        capture_output=True,
        check=False,
    )
    stdout = process.stdout.decode("UTF-8")
    assert process.returncode == int(0)
    assert check_in("URLs: https://easylist.to/easylist/easyprivacy.txt", stdout)
    assert check_in(f"TMPDIR: {converted_dir}", stdout)
    assert check_in("Content filters: class_global", stdout)
    assert check_in("Running in Convert Mode", stdout)
    assert check_in(f"Target directory for lists: {lists_dir}", stdout)
    assert check_in("Skip activation of '", stdout)
    assert Path(lists_dir).is_dir()
    assert Path(f"{lists_dir}/easyprivacy.script.action").exists()
    assert Path(f"{lists_dir}/easyprivacy.script.action").is_file()
    assert Path(f"{lists_dir}/easyprivacy.script.action").owner() == "ci_test_user"
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
