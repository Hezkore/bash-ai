#!/bin/bash
# -*- Mode: sh; coding: utf-8; indent-tabs-mode: t; tab-width: 4 -*-

# Determine the user's environment
#OS_INFO=$(uname -s)
USER_INFO=$(uname -a)
DISTRO_INFO=$(cat /etc/os-release | grep -oP '(?<=^PRETTY_NAME=").+(?="$)')

# Constants
PRE_TEXT="  "
NO_REPLY_TEXT="¯\_(ツ)_/¯"
CMD_BG_COLOR="\e[48;5;236m"
CMD_TEXT_COLOR="\e[38;5;203m"
INFO_TEXT_COLOR="\e[90;3m"
ERROR_TEXT_COLOR="\e[91m"
CANCEL_TEXT_COLOR="\e[93m"
OK_TEXT_COLOR="\e[92m"
RESET_COLOR="\e[0m"
CLEAR_LINE="\033[2K\r"
DEFAULT_EXEC_QUERY="Return a JSON object containing 'cmd' and 'info' fields. 'cmd' is the simplest POSIX Bash command for the query. 'info' provides details on what the command does."
DEFAULT_QUESTION_QUERY="Provide an answer to the following terminal-related query."
GLOBAL_QUERY="Always provide single-line, step-by-step instructions. User is always in the terminal. Query is related to $DISTRO_INFO and $USER_INFO."

# Configuration file path
CONFIG_FILE=~/.config/bai.cfg

# Check for configuration file existence
if [ ! -f "$CONFIG_FILE" ]; then
	# Initialize configuration file with default values
	{
		echo "key="
		echo ""
		echo "api=https://api.openai.com/v1/chat/completions"
		echo "model=gpt-3.5-turbo"
		echo "temp=0.1"
		echo "tokens=100"
		echo "exec_query="
		echo "question_query="
	} >> "$CONFIG_FILE"
fi

# Read configuration file
config=$(cat "$CONFIG_FILE")

# API Key
OPENAI_KEY=$(echo "${config[@]}" | grep -oP '(?<=^key=).+')
if [ -z "$OPENAI_KEY" ]; then
	 # Prompt user to input OpenAI key if not found
	echo "To use bai, please input your OpenAI key into the config file located at $CONFIG_FILE"
	exit 1
fi

# Extract OpenAI URL from configuration
OPENAI_URL=$(echo "${config[@]}" | grep -oP '(?<=^api=).+')

# Extract OpenAI model from configuration
OPENAI_MODEL=$(echo "${config[@]}" | grep -oP '(?<=^model=).+')

# Extract OpenAI temperature from configuration
OPENAI_TEMP=$(echo "${config[@]}" | grep -oP '(?<=^temp=).+')

# Extract OpenAI system execution query from configuration
OPENAI_EXEC_QUERY=$(echo "${config[@]}" | grep -oP '(?<=^exec_query=).+')

# Extract OpenAI system question query from configuration
OPENAI_QUESTION_QUERY=$(echo "${config[@]}" | grep -oP '(?<=^question_query=).+')

# Extract maximum token count from configuration
OPENAI_TOKENS=$(echo "${config[@]}" | grep -oP '(?<=^tokens=).+')

# Apply default query if none is provided
if [ -z "$OPENAI_EXEC_QUERY" ]; then
	OPENAI_EXEC_QUERY="$DEFAULT_EXEC_QUERY"
fi
if [ -z "$OPENAI_QUESTION_QUERY" ]; then
	OPENAI_QUESTION_QUERY="$DEFAULT_QUESTION_QUERY"
fi

# User AI query
USER_QUERY=$*

# Determine if we should use the question query or the execution query
if [[ "$USER_QUERY" == *"?"* ]]; then
	IS_QUESTION=true
	
	OPENAI_MESSAGES='{
        "role": "system",
        "content": "'"${OPENAI_QUESTION_QUERY} ${GLOBAL_QUERY}"'"
    },
    {
        "role": "user",
        "content": "how do I list all files?"
    },
    {
        "role": "assistant",
        "content": "Use \'${CMD_BG_COLOR}'\'${CMD_TEXT_COLOR}' ls -a \'${RESET_COLOR}'\'${INFO_TEXT_COLOR}' to list all files, including hidden ones, in the current directory"
    },
    {
        "role": "user",
        "content": "how do I recursively list all the files?"
    },
    {
        "role": "assistant",
        "content": "Use \'${CMD_BG_COLOR}'\'${CMD_TEXT_COLOR}' ls -aR \'${RESET_COLOR}'\'${INFO_TEXT_COLOR}' to list all files recursively, including hidden ones, in the current directory"
    },
    {
        "role": "user",
        "content": "how do I print hello world?"
    },
    {
        "role": "assistant",
        "content": "Type \'${CMD_BG_COLOR}'\'${CMD_TEXT_COLOR}' echo \\\"hello world\\\" \'${RESET_COLOR}'\'${INFO_TEXT_COLOR}' and press \'${RESET_COLOR}'Enter\'${INFO_TEXT_COLOR}' to print \\\"hello world\\\""
    },
    {
        "role": "user",
        "content": "how do autocomplete commands?"
    },
    {
        "role": "assistant",
        "content": "Press the \'${RESET_COLOR}'Tab\'${INFO_TEXT_COLOR}' key to autocomplete commands, file names, and directories"
    },'
else
	IS_QUESTION=false
	
	OPENAI_MESSAGES='{
        "role": "system",
        "content": "'"${OPENAI_EXEC_QUERY} ${GLOBAL_QUERY}"'"
    },
    {
        "role": "user",
        "content": "list all files"
    },
    {
        "role": "assistant",
        "content": "{ \"cmd\": \"ls -a\", \"info\": \"list all files, including hidden ones, in the current directory\" }"
    },
    {
        "role": "user",
        "content": "recursively list all the files"
    },
    {
        "role": "assistant",
        "content": "{ \"cmd\": \"ls -aR\", \"info\": \"list all files recursively, including hidden ones, in the current directory\" }"
    },
    {
        "role": "user",
        "content": "print hello world"
    },
    {
        "role": "assistant",
        "content": "{ \"cmd\": \"echo \\\"hello world\\\"\", \"info\": \"print the text \\\"hello world\\\" to the terminal\" }"
    },'
fi

# Notify the user about our progress
echo
echo -ne "${PRE_TEXT}Thinking...\r"

# Send request to OpenAI API
RESPONSE=$(curl -s -X POST -H "Authorization:Bearer $OPENAI_KEY" -H "Content-Type:application/json" -d '{
	"model": "'"$OPENAI_MODEL"'",
	"max_tokens": '"$OPENAI_TOKENS"',
	"temperature": '"$OPENAI_TEMP"',
	"messages": [
		'"$OPENAI_MESSAGES"'
		{
			"role": "user",
			"content": "'"${USER_QUERY}"'"
		}
	]
}' "$OPENAI_URL")

# Extract the reply from the JSON response
REPLY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' | sed "s/'//g")

# Process the reply
echo -ne "$CLEAR_LINE\r"
if [ -z "$REPLY" ]; then
	# We didn't get a reply
	echo "${PRE_TEXT}${NO_REPLY_TEXT}"
	exit 1
fi

# Determine if this is regarding a question or not
if [ "$IS_QUESTION" = false ]; then
	# Extract command from response
	CMD=$(echo "$REPLY" | jq -r '.cmd')
	if [ -z "$CMD" ]; then
		# If command is empty, print no reply text
		echo
		echo "${PRE_TEXT}${NO_REPLY_TEXT}"
		exit 1
	fi
	
	# Extract information from response
	INFO=$(echo "$REPLY" | jq -r '.info')
	if [ -z "$info" ]; then
		info="warning: no information"
	fi
	
	# Print command and information
	echo -e "${PRE_TEXT}${CMD_BG_COLOR}${CMD_TEXT_COLOR} ${CMD} ${RESET_COLOR}"
	echo
	echo -e "${PRE_TEXT}${INFO_TEXT_COLOR}${INFO}${RESET_COLOR}"
	echo
	
	# Ask for user command confirmation
	echo -n "${PRE_TEXT}execute command? [y/e/N]: "
	read -n 1 -r -s answer
	
	# Did the user want to edit the command?
	if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
		echo "yes";echo
		eval "$CMD"
		
		# Test if command was successful
		ret=$?
		echo
		if [ $ret -eq 0 ]; then
			# OK
			echo -e "${OK_TEXT_COLOR}[ok]${RESET_COLOR}"
		else
			# ERROR
			echo -e "${ERROR_TEXT_COLOR}[error]${RESET_COLOR}"
		fi
	elif [ "$answer" == "E" ] || [ "$answer" == "e" ]; then
		echo -ne "$CLEAR_LINE\r"
		read -e -r -p "${PRE_TEXT}edit command: " -i "$CMD" CMD
		echo
		eval "$CMD"
		
		# Test if edited command was successful
		ret=$?
		echo
		if [ $ret -eq 0 ]; then
			# OK
			echo -e "${OK_TEXT_COLOR}[ok]${RESET_COLOR}"
		else
			# ERROR
			echo -e "${ERROR_TEXT_COLOR}[error]${RESET_COLOR}"
		fi
	else
		# CANCEL
		echo "no";echo
		echo -e "${CANCEL_TEXT_COLOR}[cancel]${RESET_COLOR}"
	fi
	echo
	
	exit 0
else
	# This is a question
	echo -e "${PRE_TEXT}${INFO_TEXT_COLOR}${REPLY} ${RESET_COLOR}"
	echo
	exit 0
fi