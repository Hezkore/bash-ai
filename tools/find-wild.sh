#!/bin/bash
# -*- Mode: sh; coding: utf-8; indent-tabs-mode: t; tab-width: 4 -*-

# Enables Bash AI to search for files and directories and forces wildcards

init() {
	echo '{
		"type": "function",
		"function": {
			"name": "find-wildcard",
			"description": "Search for any file or directory. Please always use -iname and never -name.",
			"parameters": {
				"type": "object",
				"properties": {
					"args": {
						"type": "string",
						"description": "The arguments to pass to the find command"
					}
				},
				"required": [
					"args"
				]
			}
		}
	}'
}

execute() {
	local args
	args=$(echo "$1" | jq -r '.args')
	args=$(echo "$args" | sed -E 's/(-i?name) "([^"]*)"/\1 "*\2*"/g; s/(-i?name) ([^ ]*)/\1 "*\2*"/g')
	output=$(eval find $args 2>&1 | { grep -v "Permission denied" || true; })
	if [ -z "$output" ]; then
		echo "Not found"
	else
		echo "$output"
	fi
}