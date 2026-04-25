#!/bin/bash

for f in /docker-entrypoint.d/*.sh; do
	if [ -f "$f" ]; then
		source "$f"
	fi
done

exec "$@"
