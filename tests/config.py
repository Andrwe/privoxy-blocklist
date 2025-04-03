"""Configuration of test suite to configure tests."""

from conftest import check_in, check_not_in

content_removed = [
    "ad_970x250",  # class match: https://www.iphoneitalia.com/
    "sellwild-loader",  # id match ###
    "AdRight2",  # class match with element having multiple classes
    "data-taboola-options",  # attribute match ##[
    "data-freestar-ad id",  # combined attribute match
    'data-role="tile-ads-module"',  # attribute exact match
    'onclick="content.ad/"',  # attribute contain match
    'class="adDisplay-module_foobar"',  # attribute startswith match
    'onclick="location.href=\'https://1337x.vpnonly.site/"',  # attribute startswith match ##[*^=
]
content_exists = [
    "ajlkl",  # should exist, although one element is removed by privoxy
    '"adDisplay-modul"',  # should exist
]

# FIXME: see https://github.com/Andrwe/privoxy-blocklist/issues/35
urls_allowed = ["duckduckgo.com/", "hs-exp.jp/ads/"]
urls_allowed = ["duckduckgo.com/"]

# FIXME: implement regex-filter for domains, e.g.
#   /^https?:\/\/s3\.*.*\.amazonaws\.com\/[a-f0-9]{45,}\/[a-f,0-9]{8,10}$/$script,
#       third-party,xmlhttprequest,domain=~amazon.com
urls_blocked = [
    "andrwe.org/ads/",
    "andrwe.jp/ads/",
    "pubfeed.linkby.com",
    f"s3.{'a' * 6}.amazonaws.com/{'0123abcd' * 6}/{'ab,12' * 2}/",
]
urls_blocked = ["andrwe.org/ads/", "andrwe.jp/ads/", "pubfeed.linkby.com"]

config_checks = {
    "url_extended_config.conf": [
        (
            check_in,
            "Processing https://raw.githubusercontent.com/easylist/easylist/master/"
            "easylist/easylist_allowlist_general_hide.txt",
        ),
        (
            check_in,
            "Processing https://easylist-downloads.adblockplus.org/easylistgermany.txt",
        ),
        (
            check_in,
            "The list recieved from https://raw.githubusercontent.com/easylist/easylist/master"
            "/easylist/easylist_allowlist_general_hide.txt does not contain AdblockPlus list "
            "header. Try to process anyway.",
        ),
        (
            check_not_in,
            "created and added image handler",
        ),
    ],
    "debugging.conf": [
        (
            check_in,
            "Processing https://easylist-downloads.adblockplus.org/easylistgermany.txt",
        ),
        (
            check_not_in,
            "does not contain AdblockPlus list header.",
        ),
        (
            check_in,
            "Resolving easylist-downloads.adblockplus.org",
        ),
        (
            check_in,
            "created and added image handler",
        ),
    ],
}
