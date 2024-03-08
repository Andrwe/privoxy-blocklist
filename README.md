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

### Content Filter

By default `privoxy-blocklist` only generates URL based filter rules as content filtering may slowdown proxying a lot.
During tests I had requests that took up to 4 minutes.

To activate content filters specify the corresponding filter types either in the configuraiton file or via cli-flag `-f`, e.g.:

```bash
privoxy-blocklist.sh -f attribute_global_name -f attribute_global_exact -f attribute_global_contain -f attribute_global_startswith -f attribute_global_endswith -f class_global -f id_global
```
To see all supported filter types check the help `privoxy-blocklist.sh -h`.

Content filtering for HTTPS URLs requires Privoxy to be compiled with [`FEATURE_HTTPS_INSPECTION`](https://www.privoxy.org/user-manual/installation.html#INSTALLATION-SOURCE) and [HTTPS inspection](https://www.privoxy.org/user-manual/config.html#HTTPS-INSPECTION-DIRECTIVES) configured.
Example commands for the configuration can be found in [install_deps.sh](https://github.com/Andrwe/privoxy-blocklist/blob/main/helper/install_deps.sh)

Without `FEATURE_HTTPS_INSPECTION` content filtering only works for unencrypted HTTP-URLs.

If the feature is enabled can be tested on http://config.privoxy.org/show-status. Just open with page via your Privoxy and search for `FEATURE_HTTPS_INSPECTION`.

Some distributions provide Privoxy with HTTPS support enabled.
The following table shows support status of some tested distributions:

| Distribution | HTTPS Support |
| ------------ | ------------- |
| alpine |   no   |
| OpenWRT |   no   |
| TurrisOS |   no   |
| Ubuntu |   yes   |

## Installation

1. Install all dependencies:
   * privoxy
   * sed
   * grep
   * bash
   * wget
   * can be simplified by running [helper/install\_deps.sh](https://raw.githubusercontent.com/Andrwe/privoxy-blocklist/main/helper/install_deps.sh) which support Debian, ArchLinux and Alpine based installation
1. Download `privoxy-blocklist.sh` from the asset list of latest [release](https://github.com/Andrwe/privoxy-blocklist/releases)

## Feature Support

The following table shows features of AdBlock Plus filters and there status within privoxy-blocklist:

| Feature | Type | Status | Test |
| ------- | ---- | ------ | ---- |
| `:-abp-contains()` | extended CSS selector | :question: | :question: |
| `:-abp-has()` | extended CSS selector | :question: | :question: |
| `:-abp-properties()` | extended CSS selector | :question: | :question: |
| `\|\|…` | block domain matching excluding scheme | :white_check_mark: | :white_check_mark: |
| `\|…\|` | block exact domain matching including scheme | :question: | :question: |
| `!…` | comments | :white_check_mark: | |
| `csp=` | filter options | :question: | :question: |
| `##.class` | global CSS attribute selector with matching for class | :white_check_mark: (via `-f class_global`) | :white_check_mark: |
| `###id` | global CSS attribute selector with matching for id | :white_check_mark: (via `-f id_global`) | :white_check_mark: |
| `##[attribute]` | global CSS attribute selector with matching for attribute-name | :white_check_mark: (via `-f attribute_global_name`) | :white_check_mark: |
| `##[attribute=value]` | global CSS attribute selector with matching for attribute-value pair | :white_check_mark: (via `-f attribute_global_exact`) | :white_check_mark: |
| `##[attribute^=value]` | global CSS attribute selector with matching for attribute with value starting with | :white_check_mark: (via `-f attribute_global_startswith`) | :white_check_mark: |
| `##[attribute$=value]` | global CSS attribute selector with matching for attribute with value ending with | :white_check_mark: (via `-f attribute_global_endswith`) | :white_check_mark: |
| `##[attribute*=value]` | global CSS attribute selector with matching for attribute with value containing | :white_check_mark: (via `-f attribute_global_contain`) | :white_check_mark: |
| `##html-tag[attribute]` | global CSS attribute selector for html-tag with matching for attribute-name | :construction: | :construction: |
| `##html-tag[attribute=value]` | global CSS attribute selector for html-tag with matching for attribute-value pair | :construction: | :construction: |
| `##html-tag[attribute^=value]` | global CSS attribute selector for html-tag with matching for attribute with value starting with | :construction: | :construction: |
| `##html-tag[attribute$=value]` | global CSS attribute selector for html-tag with matching for attribute with value ending with | :construction: | :construction: |
| `##html-tag[attribute*=value]` | global CSS attribute selector for html-tag with matching for attribute with value containing | :construction: | :construction: |
| `[…]#$#` | domain based CSS selector - Snippet filter | :question: | :question: |
| `[…]##` | domain based CSS selector - Element hiding | :question: | :question: |
| `[…]#?#` | domain based CSS selector - Element hiding emulation | :question: | :question: |
| `[…]#@#` | domain based CSS selector - Element hiding exception | :question: | :question: |
| `document` | filter options | :question: | :question: |
| `~domain=` | filter options | :question: | :question: |
| `domain=` | filter options | :question: | :question: |
| `~elemhide` | filter options | :question: | :question: |
| `elemhide` | filter options | :question: | :question: |
| `@@\|\|…` | exception for domain blocking rules | :white_check_mark: | :construction: |
| `font` | filter options | :question: | :question: |
| `genericblock` | filter options | :question: | :question: |
| `generichide` | filter options | :question: | :question: |
| `~image` | filter options | :question: | :question: |
| `image` | filter options | :white_check_mark: | :construction: |
| `match-case` | filter options | :question: | :question: |
| `media` | filter options | :question: | :question: |
| `~object` | filter options | :question: | :question: |
| `object` | filter options | :question: | :question: |
| `~other` | filter options | :question: | :question: |
| `other` | filter options | :question: | :question: |
| `~ping` | filter options | :question: | :question: |
| `ping` | filter options | :question: | :question: |
| `popup` | filter options | :question: | :question: |
| `rewrite=` | filter options | :question: | :question: |
| `~script` | filter options | :question: | :question: |
| `script`  | filter options | :question: | :question: |
| `sitekey=` | filter options | :question: | :question: |
| `~stylesheet` | filter options | :question: | :question: |
| `stylesheet` | filter options | :question: | :question: |
| `~subdocument` | filter options | :question: | :question: |
| `subdocument` | filter options | :question: | :question: |
| `~third-party` | filter options | :question: | :question: |
| `third-party` | filter options | :question: | :question: |
| `~webrtc` | filter options | :question: | :question: |
| `webrtc` | filter options | :question: | :question: |
| `~websocket` | filter options | :question: | :question: |
| `websocket` | filter options | :question: | :question: |
| `~xmlhttprequest` | filter options | :question: | :question: |
| `xmlhttprequest` | filter options | :question: | :question: |

* :question: => status must be checked
* :white_check_mark: => implemented
* :construction: => work in progress

Sources:

* [Adblock Plus Help](https://help.adblockplus.org/hc/en-us/articles/360062733293#options)
* [Adblock Plus Cheatsheet](https://adblockplus.org/filter-cheatsheet)

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
