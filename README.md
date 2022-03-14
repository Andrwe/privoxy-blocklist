privoxy-blocklist
=================

[![Test Suite](https://github.com/Andrwe/privoxy-blocklist/actions/workflows/pytest.yml/badge.svg)](https://github.com/Andrwe/privoxy-blocklist/actions/workflows/pytest.yml)
[![GitHub release](https://img.shields.io/github/release/Andrwe/privoxy-blocklist?include_prereleases=&sort=semver&color=blue)](https://github.com/Andrwe/privoxy-blocklist/releases/)
[![License](https://img.shields.io/badge/License-UNLICENSE-blue)](#license)
[![pre-commit.ci status](https://results.pre-commit.ci/badge/github/Andrwe/privoxy-blocklist/master.svg)](https://results.pre-commit.ci/latest/github/Andrwe/privoxy-blocklist/master)

Script converting AdBlock Plus rules into privoxy format.

## How does it work

The script `privoxy-blocklist.sh` downloads AdBlock Plus filter files and generates privoxy compatible filter and action files based on these.
After the generation is done it modifies the privoxy configuration files `/etc/privoxy/config` to import the generated files.

Due to this behaviour the script must run as root user to be able to modify the privoxy configuration file.

## Usage

Either run `privoxy-blocklist.sh` manually with root privileges (e.g., `sudo privoxy-blocklist.sh`) or via root cronjob.

## Development

### Release

The release process is automated via github action [Release](https://github.com/Andrwe/privoxy-blocklist/actions/workflows/release.yml) and triggered by pushing a tag to the `main` branch.

The following tags are recognized:

| Tag-Schema | Result |
| ---------- | ------ |
| `[0-9]+.[0-9]+.[0-9]+` | create public release e.g., 0.4.0 |
| `[0-9]+.[0-9]+.[0-9]+-a` | create private alpha release e.g., 0.4.0-a (only visible to collaborators) |
| `[0-9]+.[0-9]+.[0-9]+-rc` | create public release candidate e.g., 0.4.0-rc (pre-release) |

### Tests

Code changes must be tested to ensure that all functionality is working as intended.
For that a pytest based test suite is maintained and runs on every pull request within [Gitlab Actions](https://github.com/Andrwe/privoxy-blocklist/actions).

#### Run Local Tests

The test suite is designed to run within a docker container based on the definition of this repository.
It is currently only tested on Ubuntu Linux but should work on every system with a POSIX compliant shell and docker.

To start all tests of the test suite just run:
```
./tests/run.sh
```

To start a single test file you can run:
```
./tests/run.sh tests/test_….py
```

To start all tests on ubuntu:
```
./tests/run.sh -o ubuntu
```

The whole process simplified by [./tests/run.sh](https://github.com/Andrwe/privoxy-blocklist/blob/master/tests/run.sh) runs the following:

1. build docker image based on [project Dockerfile](https://github.com/Andrwe/privoxy-blocklist/blob/master/Dockerfile)
1. start container based on created image with git repository mounted to `/app` and persistent volume for pytest-cache mounted to `/pytest_cache`

Within the container all pytest magic happens and all scripts matching `test_*.py` within `tests/` are executed.


## Kudos

* [Badge Generator](https://michaelcurrin.github.io/badge-generator/#/) for providing easy method to generate badges/shields
