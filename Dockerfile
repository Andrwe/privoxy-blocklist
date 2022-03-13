FROM		alpine:latest
COPY		tests/requirements.txt /requirements.txt
COPY		helper/install_deps.sh /install_deps.sh
COPY		privoxy-blocklist.sh /privoxy-blocklist.sh
# hadolint ignore=DL3018
RUN		apk add --no-cache --quiet build-base linux-headers py3-pip python3-dev \
			&& pip install --no-cache-dir -qr /requirements.txt \
			&& rm -f /requirements.txt \
			&& install -d -o root -g root /pytest_cache \
			&& /install_deps.sh \
			&& rm -f /install_deps.sh \
			&& bash -c "for f in /etc/privoxy/*.new; do cp \$f \${f%.*};done"
WORKDIR		/app
ENTRYPOINT	["pytest", "-v", "-s", "-o", "cache_dir=/pytest_cache", "--color", "yes"]
