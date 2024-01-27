#!/bin/bash
# -*- Mode: sh; coding: utf-8; indent-tabs-mode: t; tab-width: 4 -*-

# Enables Bash AI to list directory content

init() {
	echo '{
		"type": "function",
		"function": {
			"name": "ls",
			"description": "Get content of from any directory. Find correct name for file or directory. Fix directory or file name typos.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "The absolute path e.g. /home/user/Download to list"
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
	output=$(ls -1F "$path" 2>&1)
	if [ $? -eq 0 ]; then
		echo "$output" | awk '{print "\"" $0 "\""}'
	else
		echo "$output"
	fi
}