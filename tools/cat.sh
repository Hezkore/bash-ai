#!/bin/bash
# -*- Mode: sh; coding: utf-8; indent-tabs-mode: t; tab-width: 4 -*-

# Enables Bash AI to see file content

init() {
	echo '{
		"type": "function",
		"function": {
			"name": "cat",
			"description": "Use this to get the content of any file. Do not use on binary files.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "The absolute path e.g. /home/user/test.txt"
					}
				},
				"required": [
					"path"
				]
			}
		}
	}'
}

execute() {
	local path
	path=$(echo "$1" | jq -r '.path')
	output=$(awk '{printf "LINE %d: %s\\\\n", NR, $0}' "$path" 2>&1)
	if [ $? -eq 0 ]; then
		echo -e "$output"
	else
		echo "$output"
	fi
}