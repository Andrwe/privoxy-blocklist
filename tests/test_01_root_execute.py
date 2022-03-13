"""
test execution as root
"""


from pathlib import Path
import pytest
import pytestshellutils


def test_first_run(shell, privoxy_blocklist):
    """test initial run which should fail"""
    if Path("/etc/conf.d/privoxy-blacklist").exists():
        pytest.skip("first run already happened, skipping")
    ret = shell.run("sudo", privoxy_blocklist)
    assert ret.returncode == 1
    assert "Creating default one and exiting" in ret.stdout


def test_next_run(shell, privoxy_blocklist):
    """test followup runs"""
    assert shell.run("sudo", privoxy_blocklist).returncode == 0
    assert (
        shell.run(
            "/usr/sbin/privoxy", "--no-daemon", "--config-test", "/etc/privoxy/config"
        ).returncode
        == 0
    )


def test_start_privoxy(shell):
    """test start of privoxy"""
    run = pytestshellutils.shell.Daemon(
        script_name="/usr/sbin/privoxy", cwd="/etc/privoxy", start_timeout=10
    )
    assert run.start()
    assert run.is_running()
    assert shell.run("pgrep", "-f", "/usr/sbin/privoxy").returncode == 0
