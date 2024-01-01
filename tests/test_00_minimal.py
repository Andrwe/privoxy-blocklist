"""Test the minimum requirements for repo."""

from pathlib import Path


def test_permissions() -> None:
    """Test file permissions."""
    git_root = Path(__file__).parent.parent.absolute()
    executables = ["privoxy-blocklist.sh", "helper/install_deps.sh", "tests/run.sh"]
    non_executables = [
        ".ci_config/bandit.yml",
        ".ci_config/prospector.yaml",
        ".editorconfig",
        ".flake8",
        ".github/release.yml",
        ".github/workflows/pytest.yml",
        ".github/workflows/release.yml",
        "LICENSE",
        ".pre-commit-config.yaml",
        "README.md",
        "tests/conftest.py",
        "tests/Dockerfile_alpine",
        "tests/Dockerfile_ubuntu",
        "tests/requirements.txt",
        "tests/test_00_minimal.py",
        "tests/test_01_root_execute.py",
    ]
    for filepath in executables:
        path = git_root / filepath
        assert path.exists()
        assert path.is_file()
        # need to check for all 3 exec-versions due to CICD runs
        assert path.stat().st_mode in [0o100755, 0o100775, 0o100777]
    for filepath in non_executables:
        path = git_root / filepath
        assert path.exists()
        assert path.is_file()
        assert path.stat().st_mode in [0o100644, 0o100664, 0o100666]


def test_privoxy_setup(shell) -> None:
    """Test if privoxy is set up correctly."""
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
