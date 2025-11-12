#!/bin/bash
set -x
for f in /docker-entrypoint.d/*; do
	if [ -f "$f" ]; then
		source "$f"
	fi
done

exec "$@"
