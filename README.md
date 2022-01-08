privoxy-blocklist
=================

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

## Kudos

* [Badge Generator](https://michaelcurrin.github.io/badge-generator/#/) for providing easy method to generate badges/shields
