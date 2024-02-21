#!/bin/bash
# -*- Mode: sh; coding: utf-8; indent-tabs-mode: t; tab-width: 4 -*-

# Enables Bash AI to search for files and directories and forces wildcards

init() {
	echo '{
		"type": "function",
		"function": {
			"name": "find-wildcard",
			"description": "Use this to find any file or directory.",
			"parameters": {
				"type": "object",
				"properties": {
					"path": {
						"type": "string",
						"description": "The path to search recursivly from"
					},
					"name": {
						"type": "string",
						"description": "The iname to search for"
					}
				},
				"required": [
					"path",
					"name"
				]
			}
		}
	}'
}

execute() {
	local path
	local name
	path=$(echo "$1" | jq -r '.path')
	name=$(echo "$1" | jq -r '.name')
	name="*$name*"
    output=$(eval "find $path -iname '$name'" 2>/dev/null)
    if [ -n "$output" ]; then
		output=$(echo "$output" | awk '{printf "%s\\n", $0}')
		echo "$output"
    else
        echo "Not found"
    fi
}