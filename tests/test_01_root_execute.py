"""
test execution as root
"""


from tempfile import gettempdir
from pathlib import Path
from shutil import which
import pytestshellutils


def test_missing_deps(shell, privoxy_blocklist):
    """test error when dependency is missing"""
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


def test_config_generator(shell, privoxy_blocklist):
    """test config generator with default path"""
    config = Path("/etc/privoxy-blocklist.conf")
    if config.exists():
        config.unlink()
    ret = shell.run("sudo", privoxy_blocklist)
    assert ret.returncode == 1
    assert "Creating default one and exiting" in ret.stdout
    assert config.exists()


def test_custom_config_generator(shell, privoxy_blocklist):
    """test config generator with custom path"""
    config = Path(f"{gettempdir()}/privoxy-blocklist")
    if config.exists():
        config.unlink()
    ret = shell.run("sudo", privoxy_blocklist, "-c", str(config))
    assert ret.returncode == 1
    assert "Creating default one and exiting" in ret.stdout
    assert config.exists()


def test_next_run(shell, privoxy_blocklist):
    """test followup runs"""
    ret_script = shell.run("sudo", privoxy_blocklist)
    assert ret_script.returncode == 0
    ret_privo = shell.run(
        "/usr/sbin/privoxy", "--no-daemon", "--config-test", "/etc/privoxy/config"
    )
    assert ret_privo.returncode == 0


def test_start_privoxy(shell):
    """test start of privoxy"""
    run = pytestshellutils.shell.Daemon(
        script_name="/usr/sbin/privoxy", cwd="/etc/privoxy", start_timeout=10
    )
    assert run.start()
    assert run.is_running()
    assert shell.run("pgrep", "-f", "/usr/sbin/privoxy").returncode == 0
