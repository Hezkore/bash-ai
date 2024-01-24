#!/bin/bash
# -*- Mode: sh; coding: utf-8; indent-tabs-mode: t; tab-width: 4 -*-

REPO_OWNER="Hezkore"
REPO_NAME="bash-ai"
REPO_BRANCH="main"
REPO_SCRIPT="bai.sh"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}/${REPO_SCRIPT}"
BIN_DIR="/usr/local/bin"
BIN_NAME="bai"
TMP_FILE=$(mktemp)

# Download the script file
echo
echo "Downloading Bash AI..."
curl -q --fail --location --progress-bar --output "$TMP_FILE" "$SCRIPT_URL"
ret=$?
echo

# Check if curl succeeded
if [ $ret -ne 0 ]; then
	echo "Failed to download $REPO_SCRIPT from $SCRIPT_URL"
	exit 1
fi
if [ ! -f "$TMP_FILE" ]; then # curl succeeded but file doesn't exist
	echo "Failed to create $TMP_FILE"
	exit 1
fi
if [ ! -s "$TMP_FILE" ]; then # file exists but is empty
	echo "Downloaded $TMP_FILE is empty"
	exit 1
fi

# Move the temp file to bin dir with a proper name
echo "Installing Bash AI to $BIN_DIR..."
sudo mv "$TMP_FILE" "$BIN_DIR/$BIN_NAME"
if [ ! -f "$BIN_DIR/$BIN_NAME" ]; then
	echo "Failed to install Bash AI to $BIN_DIR"
	exit 1
fi

# Make the bin executable
sudo chmod +x "$BIN_DIR/$BIN_NAME"
if [ ! -x "$BIN_DIR/$BIN_NAME" ]; then
	echo "Failed to make Bash AI executable"
	exit 1
fi

# Done!
echo
echo "Installation completed successfully!"
echo "Run '${BIN_NAME}' to start Bash AI (you may need to restart your terminal)"
echo "Visit https://github.com/${REPO_OWNER}/${REPO_NAME} for more information"
exit 0