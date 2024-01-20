#!/bin/bash
# -*- Mode: sh; coding: utf-8; indent-tabs-mode: t; tab-width: 4 -*-

# Bash AI
# https://github.com/Hezkore/bash-ai

# Determine the user's environment
USER_INFO=$(uname -a)
DISTRO_INFO=$(cat /etc/os-release | grep -oP '(?<=^PRETTY_NAME=").+(?="$)')

# Constants
VERSION="1.0"
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
DEFAULT_EXEC_QUERY="Return nothing but a JSON object containing 'cmd' and 'info' fields. 'cmd' is the simplest Bash command for the query. 'info' provides details on what the command does."
DEFAULT_QUESTION_QUERY="Return nothing but a short text answer to the following terminal-related query."
GLOBAL_QUERY="You are Bash AI (bai) v${VERSION}. Always provide single-line, step-by-step instructions. User is always in the terminal. Query is related distro $DISTRO_INFO and $USER_INFO. Use only POSIX-compliant commands. Username is $USER at $HOME"
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

# Extract maximum token count from configuration
OPENAI_TOKENS=$(echo "${config[@]}" | grep -oP '(?<=^tokens=).+')

# Test if high contrast mode is set in configuration
HI_CONTRAST=$(echo "${config[@]}" | grep -oP '(?<=^hi_contrast=).+')
if [ "$HI_CONTRAST" = true ]; then
	INFO_TEXT_COLOR="$RESET_COLOR"
fi

# Set default query if not provided in configuration
if [ -z "$OPENAI_EXEC_QUERY" ]; then
	OPENAI_EXEC_QUERY="$DEFAULT_EXEC_QUERY"
fi
if [ -z "$OPENAI_QUESTION_QUERY" ]; then
	OPENAI_QUESTION_QUERY="$DEFAULT_QUESTION_QUERY"
fi

# Helper functions
print_info() {
	echo -e "${PRE_TEXT}${INFO_TEXT_COLOR}$1${RESET_COLOR}"
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
	echo -e "${PRE_TEXT}${CMD_BG_COLOR}${CMD_TEXT_COLOR} $1 ${RESET_COLOR}"
	echo
}

print() {
	echo -e "${PRE_TEXT}$1"
}

json_safe() {
	echo "$1" | perl -pe 's/\\/\\\\/g; s/"/\\"/g; s/\033/\\\\033/g; s/\n/\\n/g; s/\r/\\r/g; s/\t/\\t/g'
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
		echo "${output#*"$0": line *: }"
		print_error "[error]"
		rm "$tmpfile"
		
		# Ask if we should examine the error
		echo -n "${PRE_TEXT}examine error? [y/N]: "
		echo -ne "$SHOW_CURSOR"
		read -n 1 -r -s answer
		
		# Did the user want to examine the error?
		if [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
			echo "yes";echo
			USER_QUERY="You executed \"$1\". Which returned error \"$output\". Explain the error message and how to fix it in less than $OPENAI_TOKENS characters. Or return nothing but a JSON object with 'cmd' to fix it and 'info' explaining what happened and why cmd will fix it."
			NEEDS_TO_RUN=true
		else
			echo "no";echo
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

# While we're in Interactive Mode or it's the first run
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
	if [[ "$USER_QUERY" == *"?"* ]]; then
		# QUESTION
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
		# COMMAND
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
	
	# Send request to OpenAI API
	RESPONSE=$(curl -s -X POST -H "Authorization:Bearer $OPENAI_KEY" -H "Content-Type:application/json" -d '{
		"model": "'"$OPENAI_MODEL"'",
		"max_tokens": '"$OPENAI_TOKENS"',
		"temperature": '"$OPENAI_TEMP"',
		"messages": [
			'"$OPENAI_MESSAGES"'
			'"$HISTORY_MESSAGES"'
			{
				"role": "user",
				"content": "'"${USER_QUERY}"'"
			}
		]
	}' "$OPENAI_URL")
	
	# Stop the spinner
	kill $spinner_pid
	wait $spinner_pid 2>/dev/null
	
	# Reset the needs to run flag
	NEEDS_TO_RUN=false
	
	# Extract the reply from the JSON response
	REPLY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' | sed "s/'//g")
	
	# Process the reply
	echo -ne "$CLEAR_LINE\r"
	if [ -z "$REPLY" ]; then
		# We didn't get a reply
		print_info "$NO_REPLY_TEXT"
		echo -ne "$SHOW_CURSOR"
		# Reset user query
		USER_QUERY=""
	else
		# We got a reply
		# Append it to history
		HISTORY_MESSAGES+='{
			"role": "user",
			"content": "'"${USER_QUERY}"'"
		},
		{
			"role": "assistant",
			"content": "'"$(json_safe "$REPLY")"'"
		},'
		
		# Reset user query
		USER_QUERY=""
		
		# Extract command from the reply
		CMD=$(echo "$REPLY" | jq -e -r '.cmd' 2>/dev/null)
		if [ $? -ne 0 ] || [ -z "$CMD" ]; then
			# No command, show reply
			print_info "$REPLY"
			echo -ne "$SHOW_CURSOR"
		else
			# Extract information from response
			INFO=$(echo "$REPLY" | jq -r '.info')
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
exit 0