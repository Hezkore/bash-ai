#!/bin/bash
# -*- Mode: sh; coding: utf-8; indent-tabs-mode: t; tab-width: 4 -*-

# Bash AI
# https://github.com/Hezkore/bash-ai

# Determine the user's environment
UNIX_NAME=$(uname -srp)
# Attempt tp fetch distro info from
if [ -x "$(command -v lsb_release)" ]; then
	DISTRO_INFO=$(lsb_release -ds | sed 's/^"//;s/"$//')
elif [ -f "/etc/os-release" ]; then
	DISTRO_INFO=$(grep -oP '(?<=^PRETTY_NAME=").+(?="$)' /etc/os-release)
fi
# If we failed to fetch distro info, we'll use mark it as unknown
if [ ${#DISTRO_INFO} -le 1 ]; then
	DISTRO_INFO="Unknown"
fi

# Constants
VERSION="1.0.1"
PRE_TEXT="  "
NO_REPLY_TEXT="¯\_(ツ)_/¯"
CMD_BG_COLOR="\e[48;5;236m"
CMD_TEXT_COLOR="\e[38;5;203m"
INFO_TEXT_COLOR="\e[90;3m"
ERROR_TEXT_COLOR="\e[91m"
CANCEL_TEXT_COLOR="\e[93m"
OK_TEXT_COLOR="\e[92m"
TITLE_TEXT_COLOR="\e[1m"
RESET_COLOR="\e[0m"
CLEAR_LINE="\033[2K\r"
HIDE_CURSOR="\e[?25l"
SHOW_CURSOR="\e[?25h"
DEFAULT_EXEC_QUERY="Return nothing but a JSON object containing 'cmd' and 'info' fields. 'cmd' must always include a suggestion for the simplest Bash command for the query. 'info' must always include details about the actions 'cmd' will perform and the purpose of all command flags."
DEFAULT_QUESTION_QUERY="Return nothing but a JSON object containing a 'info' field. 'info' must always include a terminal-related answer to the query."
DEFAULT_ERROR_QUERY="Return nothing but a JSON object containing 'cmd' and 'info' fields. 'cmd' is optional. 'cmd' is the simplest Bash command to fix, solve or repair the error in the query. 'info' must explain what the error in the query means, why it happened, and why 'cmd' might fix it."
GLOBAL_QUERY="You are Bash AI (bai) v${VERSION}. You are a terminal assistant. We are always in the terminal. Your replies must always be single-line. You may only use POSIX-compliant commands. The query refers to \\\"$UNIX_NAME\\\" and distro \\\"$DISTRO_INFO\\\". The users username is \\\"$USER\\\" with home \\\"$HOME\\\". The users PATH environment variable is \\\"$PATH\\\"."
HISTORY_MESSAGES=""

# Configuration file path
CONFIG_FILE=~/.config/bai.cfg

# Hide the cursor while we're working
trap 'echo -ne "$SHOW_CURSOR"' EXIT
echo -e "$HIDE_CURSOR"

# Check for configuration file existence
if [ ! -f "$CONFIG_FILE" ]; then
	# Initialize configuration file with default values
	{
		echo "key="
		echo ""
		echo "hi_contrast=false"
		echo "expose_current_dir=true"
		echo "expose_dir_content=true"
		echo "max_dir_content=50"
		echo "max_history=10"
		echo "api=https://api.openai.com/v1/chat/completions"
		echo "model=gpt-3.5-turbo"
		echo "json_mode=false"
		echo "temp=0.1"
		echo "tokens=100"
		echo "exec_query="
		echo "question_query="
		echo "error_query="
	} >> "$CONFIG_FILE"
fi

# Read configuration file
config=$(cat "$CONFIG_FILE")

# API Key
OPENAI_KEY=$(echo "${config[@]}" | grep -oP '(?<=^key=).+')
if [ -z "$OPENAI_KEY" ]; then
	 # Prompt user to input OpenAI key if not found
	echo "To use Bash AI, please input your OpenAI key into the config file located at $CONFIG_FILE"
	echo -ne "$SHOW_CURSOR"
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

# Extract OpenAI system error query from configuration
OPENAI_ERROR_QUERY=$(echo "${config[@]}" | grep -oP '(?<=^error_query=).+')

# Extract maximum token count from configuration
OPENAI_TOKENS=$(echo "${config[@]}" | grep -oP '(?<=^tokens=).+')
GLOBAL_QUERY+=" All your messages must be less than $OPENAI_TOKENS tokens."

# Test if high contrast mode is set in configuration
HI_CONTRAST=$(echo "${config[@]}" | grep -oP '(?<=^hi_contrast=).+')
if [ "$HI_CONTRAST" = true ]; then
	INFO_TEXT_COLOR="$RESET_COLOR"
fi

# Test if we should expose current dir
EXPOSE_CURRENT_DIR=$(echo "${config[@]}" | grep -oP '(?<=^expose_current_dir=).+')

# Test if we should expose dir content
EXPOSE_DIR_CONTENT=$(echo "${config[@]}" | grep -oP '(?<=^expose_dir_content=).+')

# Extract maximum directory content count from configuration
MAX_DIRECTORY_CONTENT=$(echo "${config[@]}" | grep -oP '(?<=^max_dir_content=).+')

# Extract maximum history message count from configuration
MAX_HISTORY_COUNT=$(echo "${config[@]}" | grep -oP '(?<=^max_history=).+')

# Test if GPT JSON mode is set in configuration
JSON_MODE=$(echo "${config[@]}" | grep -oP '(?<=^json_mode=).+')
if [ "$JSON_MODE" = true ]; then
	JSON_MODE="\"response_format\": { \"type\": \"json_object\" },"
else
	JSON_MODE=""
fi

# Set default query if not provided in configuration
if [ -z "$OPENAI_EXEC_QUERY" ]; then
	OPENAI_EXEC_QUERY="$DEFAULT_EXEC_QUERY"
fi
if [ -z "$OPENAI_QUESTION_QUERY" ]; then
	OPENAI_QUESTION_QUERY="$DEFAULT_QUESTION_QUERY"
fi
if [ -z "$OPENAI_ERROR_QUERY" ]; then
	OPENAI_ERROR_QUERY="$DEFAULT_ERROR_QUERY"
fi

# Helper functions
print_info() {
	echo -ne "${PRE_TEXT}${INFO_TEXT_COLOR}"
	echo -n "$1"
	echo -e "${RESET_COLOR}"
	echo
}

print_ok() {
	echo -e "${OK_TEXT_COLOR}$1${RESET_COLOR}"
	echo
}

print_error() {
	echo -e "${ERROR_TEXT_COLOR}$1${RESET_COLOR}"
	echo
}

print_cancel() {
	echo -e "${CANCEL_TEXT_COLOR}$1${RESET_COLOR}"
	echo
}

print_cmd() {
	echo -ne "${PRE_TEXT}${CMD_BG_COLOR}${CMD_TEXT_COLOR}"
	echo -n " $1 "
	echo -e "${RESET_COLOR}"
	echo
}

print() {
	echo -e "${PRE_TEXT}$1"
}

json_safe() {
	echo "$1" | perl -pe 's/\\/\\\\/g; s/"/\\"/g; s/\033/\\\\033/g; s/\n/ /g; s/\r/\\r/g; s/\t/\\t/g'
}

run_cmd() {
	tmpfile=$(mktemp)
	if eval "$1" 2>"$tmpfile"; then
		# OK
		print_ok "[ok]"
		rm "$tmpfile"
		return 0
	else
		# ERROR
		output=$(cat "$tmpfile")
		LAST_ERROR="${output#*"$0": line *: }"
		echo "$LAST_ERROR"
		rm "$tmpfile"
		
		# Ask if we should examine the error
		if [ ${#LAST_ERROR} -gt 1 ]; then
			print_error "[error]"
			echo -n "${PRE_TEXT}examine error? [y/N]: "
			echo -ne "$SHOW_CURSOR"
			read -n 1 -r -s answer
			
			# Did the user want to examine the error?
			if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
				echo "yes";echo
				USER_QUERY="You executed \"$1\". Which returned error \"$LAST_ERROR\"."
				QUERY_TYPE="error"
				NEEDS_TO_RUN=true
			else
				echo "no";echo
			fi
		else
			print_cancel "[cancel]"
		fi
		return 1
	fi
}

# User AI query and Interactive Mode
USER_QUERY=$*

# Are we entering interactive mode?
if [ -z "$USER_QUERY" ]; then
	INTERACTIVE_MODE=true
	print "🤖 ${TITLE_TEXT_COLOR}Bash AI v${VERSION}${RESET_COLOR}"
	echo
	print_info "Hi! What can I help you with?"
else
	INTERACTIVE_MODE=false
	NEEDS_TO_RUN=true
fi

# While we're in Interactive Mode or NEED_TO_RUN
while [ "$INTERACTIVE_MODE" = true ] || [ "$NEEDS_TO_RUN" = true ]; do
	# We require a user query
	while [ -z "$USER_QUERY" ]; do
		# No query, prompt user for query
		echo -ne "$SHOW_CURSOR"
		read -e -r -p "Bash AI> " USER_QUERY
		echo -e "$HIDE_CURSOR"
		
		# Check if user wants to quit
		if [ "$USER_QUERY" == "exit" ]; then
			echo -ne "$SHOW_CURSOR"
			print_info "Bye!"
			exit 0
		fi
	done
	
	# Make sure the query is JSON safe
	USER_QUERY=$(json_safe "$USER_QUERY")
	
	echo -ne "$HIDE_CURSOR"
	
	# Determine if we should use the question query or the execution query
	if [ -z "$QUERY_TYPE" ]; then # If the query type is not set already
		if [[ "$USER_QUERY" == *"?"* ]]; then
			QUERY_TYPE="question"
		else
			QUERY_TYPE="execute"
		fi
	fi
	
	# Apply the correct query message history
	# The options are "execute", "question" and "error"
	if [ "$QUERY_TYPE" == "question" ]; then
		# QUESTION
		OPENAI_TEMPLATE_MESSAGES='{
			"role": "system",
			"content": "'"${GLOBAL_QUERY} ${OPENAI_QUESTION_QUERY}"'"
		},
		{
			"role": "user",
			"content": "how do I list all files?"
		},
		{
			"role": "assistant",
			"content": "{ \"info\": \"Use the \\\"ls\\\" command to with the \\\"-a\\\" flag to list all files, including hidden ones, in the current directory.\" }"
		},
		{
			"role": "user",
			"content": "how do I recursively list all the files?"
		},
		{
			"role": "assistant",
			"content": "{ \"info\": \"Use the \\\"ls\\\" command to with the \\\"-aR\\\" flag to list all files recursively, including hidden ones, in the current directory.\" }"
		},
		{
			"role": "user",
			"content": "how do I print hello world?"
		},
		{
			"role": "assistant",
			"content": "{ \"info\": \"Use the \\\"echo\\\" command to print text, and \\\"echo \\\"hello world\\\"\\\" to print your specified text.\" }"
		},
		{
			"role": "user",
			"content": "how do autocomplete commands?"
		},
		{
			"role": "assistant",
			"content": "{ \"info\": \"Press the Tab key to autocomplete commands, file names, and directories.\" }"
		}'
	elif [ "$QUERY_TYPE" == "error" ]; then
		# ERROR
		OPENAI_TEMPLATE_MESSAGES='{
			"role": "system",
			"content": "'"${GLOBAL_QUERY} ${OPENAI_ERROR_QUERY}"'"
		},
		{
			"role": "user",
			"content": "You executed \\\"start avidemux\\\". Which returned error \\\"avidemux: command not found\\\"."
		},
		{
			"role": "assistant",
			"content": "{ \"cmd\": \"sudo install avidemux\", \"info\": \"This means that the application \\\"avidemux\\\" was not found. Try installing it.\" }"
		},
		{
			"role": "user",
			"content": "You executed \\\"cd \\\"hell word\\\"\\\". Which returned error \\\"cd: hell word: No such file or directory\\\"."
		},
		{
			"role": "assistant",
			"content": "{ \"cmd\": \"cd \\\"wORLD helloz\\\"\", \"info\": \"The error indicates that the \\\"wORLD helloz\\\" directory does not exist. However, the current directory contains a \\\"hello world\\\" directory we can try instead.\" }"
		},
		{
			"role": "user",
			"content": "You executed \\\"cat \\\"in .sh.\\\"\\\". Which returned error \\\"cat: in .sh: No such file or directory\\\"."
		},
		{
			"role": "assistant",
			"content": "{ \"cmd\": \"cat \\\"install.sh\\\"\", \"info\": \"The cat command could not find the \\\"in .sh\\\" file in the current directory. However, the current directory contains a file called \\\"install.sh\\\".\" }"
		}'
	else
		# COMMAND
		OPENAI_TEMPLATE_MESSAGES='{
			"role": "system",
			"content": "'"${GLOBAL_QUERY} ${OPENAI_EXEC_QUERY}"'"
		},
		{
			"role": "user",
			"content": "list all files"
		},
		{
			"role": "assistant",
			"content": "{ \"cmd\": \"ls -a\", \"info\": \"\\\"ls\\\" with the flag \\\"-a\\\" will list all files, including hidden ones, in the current directory\" }"
		},
		{
			"role": "user",
			"content": "start avidemux"
		},
		{
			"role": "assistant",
			"content": "{ \"cmd\": \"avidemux\", \"info\": \"start the Avidemux video editor, if it is installed on the system and available for the current user\" }"
		},
		{
			"role": "user",
			"content": "print hello world"
		},
		{
			"role": "assistant",
			"content": "{ \"cmd\": \"echo \\\"hello world\\\"\", \"info\": \"\\\"echo\\\" will print text, while \\\"echo \\\"hello world\\\"\\\" will print your text\" }"
		},
		{
			"role": "user",
			"content": "remove the hello world folder"
		},
		{
			"role": "assistant",
			"content": "{ \"cmd\": \"rm -r  \\\"hello world\\\"\", \"info\": \"\\\"rm\\\" with the \\\"-r\\\" flag will remove the \\\"hello world\\\" folder and its contents recursively\" }"
		},
		{
			"role": "user",
			"content": "move into the hello world folder"
		},
		{
			"role": "assistant",
			"content": "{ \"cmd\": \"cd \\\"hello world\\\"\", \"info\": \"\\\"cd\\\" will let you change directory to \\\"hello world\\\"\" }"
		},
		{
			"role": "user",
			"content": "add /home/user/.local/bin to PATH"
		},
		{
			"role": "assistant",
			"content": "{ \"cmd\": \"export PATH=/home/user/.local/bin:PATH\", \"info\": \"\\\"export\\\" has the ability to add \\\"/some/path\\\" to your PATH for the current session. the specified path already exists in your PATH environment variable since before\" }"
		}'
	fi
	
	# Notify the user about our progress
	echo -ne "${PRE_TEXT}  Thinking..."
	
	# Start the spinner in the background
	spinner() {
		local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
		while :; do
			for (( i=0; i<${#chars}; i++ )); do
				sleep 0.1
				# Print a carriage return (\r) and then the spinner character
				echo -ne "\r${PRE_TEXT}${chars:$i:1}"
			done
		done
	}
	spinner & # Start the spinner
	spinner_pid=$! # Save the spinner's PID
	
	# If we're not in Interactive Mode, we apply the history messages from baihistory.txt in the Temp dir
	if [ "$INTERACTIVE_MODE" = false ]; then
		# Check if the history file exists
		if [ -f "/tmp/baihistory.txt" ]; then
			# Read the history file
			HISTORY_MESSAGES=$(sed 's/^\[\(.*\)\]$/,\1/' /tmp/baihistory.txt)
		fi
	fi
	
	# Directory and content exposure
	tmp_msg=""
	# Check if EXPOSE_CURRENT_DIR is true
	if [ "$EXPOSE_CURRENT_DIR" = true ]; then
		tmp_msg+="User is in directory $(json_safe "$(pwd)"). "
	fi
	# Check if EXPOSE_DIR_CONTENT is true
	if [ "$EXPOSE_DIR_CONTENT" = true ]; then
		tmp_msg+="Current directory contains $(json_safe "$(ls -1F | head -n $MAX_DIRECTORY_CONTENT)")."
	fi
	# Apply the directory and content message to the message history
	HISTORY_MESSAGES+=',{
		"role": "system",
		"content": "'"${tmp_msg}"'"
	}'
	
	# Apply the user query to the message history
	HISTORY_MESSAGES+=',{
		"role": "user",
		"content": "'${USER_QUERY}'"
	}'
	
	# Construct the JSON payload
	JSON_PAYLOAD='{
		"model": "'"$OPENAI_MODEL"'",
		"max_tokens": '"$OPENAI_TOKENS"',
		"temperature": '"$OPENAI_TEMP"',
		'"$JSON_MODE"'
		"messages": [
			'"$OPENAI_TEMPLATE_MESSAGES $HISTORY_MESSAGES"'
		]
	}'
	
	# Prettify the JSON payload and verify it
	JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq .)
	
	# Send request to OpenAI API
	RESPONSE=$(curl -s -X POST -H "Authorization:Bearer $OPENAI_KEY" -H "Content-Type:application/json" -d "$JSON_PAYLOAD" "$OPENAI_URL")
	
	# Stop the spinner
	kill $spinner_pid
	wait $spinner_pid 2>/dev/null
	
	# Reset the needs to run flag
	NEEDS_TO_RUN=false
	
	# Reset the query type
	QUERY_TYPE=""
	
	# Reset user query
	USER_QUERY=""
	
	# Extract the reply from the JSON response
	REPLY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' | sed "s/'//g")
	
	# Process the reply
	echo -ne "$CLEAR_LINE\r"
	if [ -z "$REPLY" ]; then
		# We didn't get a reply
		print_info "$NO_REPLY_TEXT"
		echo -ne "$SHOW_CURSOR"
	else
		# We got a reply
		# Apply it to message history
		HISTORY_MESSAGES+=',{
			"role": "assistant",
			"content": "'"$(json_safe "$REPLY")"'"
		}'
		
		# Check the reason for stopping
		FINISH_REASON=$(echo "$RESPONSE" | jq -r '.choices[0].finish_reason')
		
		# If the finish reason isn't "stop" then we'll have a cut off info field
		if [ "$FINISH_REASON" != "stop" ]; then
			REPLY+="... nevermind, seems like I've hit my token limit. \"}"
		fi
		
		# Extract information from the reply
		INFO=$(echo "$REPLY" | jq -e -r '.info' 2>/dev/null)
		
		# Extract command from the reply
		CMD=$(echo "$REPLY" | jq -e -r '.cmd' 2>/dev/null)
		if [ $? -ne 0 ] || [ -z "$CMD" ]; then
			# Not a command
			if [ -z "$INFO" ]; then
				# No info
				print_info "$REPLY"
			else
				# Print info
				print_info "$INFO"
			fi
			echo -ne "$SHOW_CURSOR"
		else
			# Make sure some sort of information exists
			if [ -z "$INFO" ]; then
				INFO="warning: no information"
			fi
			
			# Print command and information
			print_cmd "$CMD"
			print_info "$INFO"
			
			# Ask for user command confirmation
			echo -n "${PRE_TEXT}execute command? [y/e/N]: "
			echo -ne "$SHOW_CURSOR"
			read -n 1 -r -s answer
			
			# Did the user want to edit the command?
			if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
				# RUN
				echo "yes";echo
				run_cmd "$CMD"
			elif [ "$answer" == "E" ] || [ "$answer" == "e" ]; then
				# EDIT
				echo -ne "$CLEAR_LINE\r"
				read -e -r -p "${PRE_TEXT}edit command: " -i "$CMD" CMD
				echo
				run_cmd "$CMD"
			else
				# CANCEL
				echo "no";echo
				print_cancel "[cancel]"
			fi
		fi
	fi
done

# If we're not in Interactive Mode, we save the history messages to baihistory.txt in tmp
if [ "$INTERACTIVE_MODE" = false ]; then
	# Add a dummy message at the beginning to make HISTORY_MESSAGES a valid JSON array
	HISTORY_MESSAGES_JSON="[null$HISTORY_MESSAGES]"
	
	# Get the number of messages
	HISTORY_COUNT=$(echo "$HISTORY_MESSAGES_JSON" | jq 'length')
	
	# Convert MAX_HISTORY_COUNT to an integer
	MAX_HISTORY_COUNT_INT=$((MAX_HISTORY_COUNT))
	
	# If the history is too long, remove the oldest messages
	if (( HISTORY_COUNT > MAX_HISTORY_COUNT_INT )); then
		HISTORY_MESSAGES_JSON=$(echo "$HISTORY_MESSAGES_JSON" | jq ".[-$MAX_HISTORY_COUNT_INT:]")
	fi
	
	# Remove the dummy message and write the history to the file
	echo "$HISTORY_MESSAGES_JSON" | jq '.[1:]' | jq -c . > /tmp/baihistory.txt
fi

exit 0