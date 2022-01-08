privoxy-blocklist
=================

Script converting AdBlock Plus rules into privoxy format.

## How does it work

The script `privoxy-blocklist.sh` downloads AdBlock Plus filter files and generates privoxy compatible filter and action files based on these.
After the generation is done it modifies the privoxy configuration files `/etc/privoxy/config` to import the generated files.

Due to this behaviour the script must run as root user to be able to modify the privoxy configuration file.

## Usage

Either run `privoxy-blocklist.sh` manually with root privileges (e.g., `sudo privoxy-blocklist.sh`) or via root cronjob.
