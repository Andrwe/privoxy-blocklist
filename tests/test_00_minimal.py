"""Test the minimum requirements for repo."""

from pathlib import Path

from conftest import check_privoxy_config


def test_permissions() -> None:
    """Test file permissions."""
    git_root = Path(__file__).parent.parent.absolute()
    executables = ["privoxy-blocklist.sh", "helper/install_deps.sh", "tests/run.sh"]
    non_executables = [
        ".editorconfig",
        ".github/dependabot.yml",
        ".github/release.yml",
        ".github/workflows/dependabot_validate.yml",
        ".github/workflows/pytest.yml",
        ".github/workflows/release.yml",
        ".gitignore",
        "LICENSE",
        ".pre-commit-config.yaml",
        "README.md",
        "tests/config.py",
        "tests/configs/debugging.conf",
        "tests/configs/url_extended_config.conf",
        "tests/conftest.py",
        "tests/Dockerfile_alpine",
        "tests/Dockerfile_openwrt",
        "tests/Dockerfile_ubuntu",
        "tests/requirements.txt",
        "tests/response.html",
        "tests/ruff.toml",
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


def test_privoxy_setup() -> None:
    """Test if privoxy is set up correctly."""
    config_dir = Path("/etc/privoxy/")
    for path in config_dir.iterdir():
        if not path.is_file():
            continue
        if path.suffix != ".new":
            continue
        assert Path(str(path).replace(".new", "")).exists()
    ret = check_privoxy_config()
    assert ret.returncode == 0
