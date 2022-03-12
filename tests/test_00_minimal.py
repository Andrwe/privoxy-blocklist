"""
test the minimum requirements for repo
"""

from pathlib import Path


def test_permissions():
    """test permissions"""
    for filepath in ["privoxy-blocklist.sh", "helper/install_deps.sh", "tests/run.sh"]:
        path = Path(filepath)
        assert path.exists()
        assert path.is_file()
        assert path.stat().st_mode in [0o100775, 0o100755, 0o100777]
    for filepath in [
        ".pre-commit-config.yaml",
        ".editorconfig",
        "LICENSE",
        "README.md",
        "Dockerfile",
        "tests/requirements.txt",
    ]:
        path = Path(filepath)
        assert path.exists()
        assert path.is_file()


def test_privoxy_setup(shell):
    """test if privoxy is set up correctly"""
    config_dir = Path("/etc/privoxy/")
    for path in config_dir.iterdir():
        if not path.is_file():
            continue
        if not path.suffix == ".new":
            continue
        assert Path(str(path).replace(".new", "")).exists()
    ret = shell.run(
        "/usr/sbin/privoxy", "--no-daemon", "--config-test", "/etc/privoxy/config"
    )
    assert ret.returncode == 0
