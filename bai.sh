#!/bin/bash
# -*- Mode: sh; coding: utf-8; indent-tabs-mode: t; tab-width: 4 -*-

# Bash AI
# https://github.com/Hezkore/bash-ai

# Make sure required tools are installed
if [ ! -x "$(command -v jq)" ]; then
	echo "ERROR: Bash AI requires jq to be installed."
	exit 1
fi
if [ ! -x "$(command -v curl)" ]; then
	echo "ERROR: Bash AI requires curl to be installed."
	exit 1
fi

# Determine the user's environment
UNIX_NAME=$(uname -srp)
# Attempt to fetch distro info from lsb_release or /etc/os-release
if [ -x "$(command -v lsb_release)" ]; then
	DISTRO_INFO=$(lsb_release -ds | sed 's/^"//;s/"$//')
elif [ -f "/etc/os-release" ]; then
	DISTRO_INFO=$(grep -oP '(?<=^PRETTY_NAME=").+(?="$)' /etc/os-release)
fi
# If we failed to fetch distro info, we'll mark it as unknown
if [ ${#DISTRO_INFO} -le 1 ]; then
	DISTRO_INFO="Unknown"
fi

# Version of Bash AI
VERSION="1.0.4"

# Global variables
PRE_TEXT="  "  # Prefix for text output
NO_REPLY_TEXT="¯\_(ツ)_/¯"  # Text for no reply
INTERACTIVE_INFO="Hi! Feel free to ask me anything or give me a task. Type \"exit\" when you're done."  # Text for interactive mode intro
PROGRESS_TEXT="Thinking..."
PROGRESS_ANIM="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
HISTORY_MESSAGES=""  # Placeholder for history messages, this will be updated later

# Theme colors
CMD_BG_COLOR="\e[48;5;236m"  # Background color for cmd suggestions
CMD_TEXT_COLOR="\e[38;5;203m"  # Text color for cmd suggestions
INFO_TEXT_COLOR="\e[90;3m"  # Text color for all information messages
ERROR_TEXT_COLOR="\e[91m"  # Text color for cmd errors messages
CANCEL_TEXT_COLOR="\e[93m"  # Text color cmd for cancellation message
OK_TEXT_COLOR="\e[92m"  # Text color for cmd success message
TITLE_TEXT_COLOR="\e[1m"  # Text color for the Bash AI title

# Terminal control constants
CLEAR_LINE="\033[2K\r"
HIDE_CURSOR="\e[?25l"
SHOW_CURSOR="\e[?25h"
RESET_COLOR="\e[0m"

# Default query constants, these are used as default values for different types of queries
DEFAULT_EXEC_QUERY="Return only a JSON object containing 'cmd' and 'info' fields. 'cmd' must always include a suggestion for the simplest Bash command for the query. 'info' must always be a single-line string and include details about the actions 'cmd' will perform and the purpose of all command flags."
DEFAULT_QUESTION_QUERY="Return only a JSON object containing a 'info' field. 'info' must always be a single-line string and include a terminal-related answer to the query."
DEFAULT_ERROR_QUERY="Return only a JSON object containing 'cmd' and 'info' fields. 'cmd' is optional. 'cmd' is the simplest Bash command to fix, solve or repair the error in the query. 'info' must always be a single-line string and explain what the error in the query means, why it happened, and why 'cmd' might fix it. Use your tools to find out why the error occured and offer alternatives."
DYNAMIC_SYSTEM_QUERY="" # After most user queries, we'll add some dynamic system information to the query

# Global query variable, this will be updated with specific user and system information
GLOBAL_QUERY="You are Bash AI (bai) v${VERSION}. You return nothing but a JSON object. You are a terminal assistant. We are always in the terminal. The query refers to \"$UNIX_NAME\" and distro \"$DISTRO_INFO\". The users username is \"$USER\" with home \"$HOME\". You must always use LANG $LANG and LC_TIME $LC_TIME."

# Configuration file path
CONFIG_FILE=~/.config/bai.cfg
#GLOBAL_QUERY+=" Your configuration file path \"$CONFIG_FILE\"."

# Test if we're in Vim
if [ -n "$VIM" ]; then
	CMD_BG_COLOR=""
	CMD_TEXT_COLOR=""
	INFO_TEXT_COLOR=""
	ERROR_TEXT_COLOR=""
	CANCEL_TEXT_COLOR=""
	OK_TEXT_COLOR=""
	TITLE_TEXT_COLOR=""
	CLEAR_LINE=""
	HIDE_CURSOR=""
	SHOW_CURSOR=""
	RESET_COLOR=""
	
	# Make sure system message reflects that we're in Vim
	DYNAMIC_SYSTEM_QUERY+="User is inside \"$VIM\". You are in the Vim terminal."
	
	# Use the Vim history file
	HISTORY_FILE=/tmp/baihistory_vim.txt
else
	# Use the default history file
	HISTORY_FILE=/tmp/baihistory_com.txt
fi

# Update info about history file
#GLOBAL_QUERY+=" Your message history file path is \"$HISTORY_FILE\"."

# Tools
OPENAI_TOOLS=""
TOOLS_PATH=~/.bai_tools

# Create the directory only if it doesn't exist
if [ ! -d "$TOOLS_PATH" ]; then
	mkdir -p "$TOOLS_PATH"
fi
echo "" > /tmp/bai_tool_output.txt

# Declare an associative array to store function names and script paths
declare -A TOOL_MAP

# Iterate over all files in the tools directory
for tool in "$TOOLS_PATH"/*.sh
do
	# Check if the file exists before sourcing it
	if [ -f "$tool" ]; then
		# For each file, run it in a subshell and call its `init` function
		init_output=$(source "$tool"; init 2>/dev/null)
		
		# Check the exit status of the last command.
		if [ $? -ne 0 ]; then
			echo "WARNING: $tool does not contain an init function."
		else
			# Test if the output is a valid JSON and pretty-print it.
			pretty_json=$(echo "$init_output" | jq . 2>/dev/null)
			
			if [ $? -ne 0 ]; then
				echo "ERROR: $tool init function has JSON syntax errors."
				exit 1
			else
				# Extract the type from the JSON.
				type=$(echo "$pretty_json" | jq -r '.type')
				
				# If the type is "function", extract the function name and store it in the array.
				if [ "$type" = "function" ]; then
					# Extract the function name from the JSON.
					function_name=$(echo "$pretty_json" | jq -r '.function.name')
					
					# Check if the function name already exists in the map.
					if [ -n "${TOOL_MAP[$function_name]}" ]; then
						echo "ERROR: $tool tried to claim function name \"$function_name\" which is already claimed"
						exit 1
					else
						TOOL_MAP["$function_name"]="$tool"
						OPENAI_TOOLS+="$pretty_json,"
					fi
				else
					echo "Unknown tool type \"$type\"."
				fi
			fi
		fi
	fi
done

# Strip the ending , from OPENAI_TOOLS
OPENAI_TOOLS="${OPENAI_TOOLS%,}"

# Hide the cursor while we're working
trap 'echo -ne "$SHOW_CURSOR"' EXIT # Make sure the cursor is shown when the script exits
echo -e "$HIDE_CURSOR"

# Check for configuration file existence
if [ ! -f "$CONFIG_FILE" ]; then
	# Initialize configuration file with default values
	{
		echo "key="
		echo ""
		echo "hi_contrast=false"
		echo "expose_current_dir=true"
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
#GLOBAL_QUERY+=" All your messages must be less than \"$OPENAI_TOKENS\" tokens."

# Test if high contrast mode is set in configuration
HI_CONTRAST=$(echo "${config[@]}" | grep -oP '(?<=^hi_contrast=).+')
if [ "$HI_CONTRAST" = true ]; then
	INFO_TEXT_COLOR="$RESET_COLOR"
fi

# Test if we should expose current dir
EXPOSE_CURRENT_DIR=$(echo "${config[@]}" | grep -oP '(?<=^expose_current_dir=).+')

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
	# FIX:
	# This is a bad way of doing this
	# It also misses some unsafe characters
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
				SKIP_USER_QUERY_RESET=true
			else
				echo "no";echo
			fi
		else
			print_cancel "[cancel]"
		fi
		return 1
	fi
}

run_tool() {
	TOOL_ID="$1"
	TOOL_NAME="$2"
	TOOL_ARGS="$3"
	TOOL_OUTPUT=""
	
	# Get the function TOOL_NAME from TOOL_MAP IF IT EXISTS!
	if [ -z "${TOOL_MAP[$TOOL_NAME]}" ]; then
		TOOL_SCRIPT=""
		TOOL_OUTPUT=""
	else
		TOOL_SCRIPT="${TOOL_MAP[$TOOL_NAME]}"
		
		TOOL_ARGS_READABLE=$(echo "$TOOL_ARGS" | jq -r 'to_entries|map("\(.key): \(.value)")|.[]' | paste -sd ', ')
		print_info "running tool \"$TOOL_NAME\" $TOOL_ARGS_READABLE"
		
		echo "$TOOL_NAME" >> /tmp/bai_tool_output.txt
		echo "$TOOL_ARGS_READABLE" >> /tmp/bai_tool_output.txt
		
		# Run the execute function from the TOOL_SCRIPT
		TOOL_OUTPUT=$(source "$TOOL_SCRIPT"; execute "$TOOL_ARGS")
		echo "$TOOL_OUTPUT" >> /tmp/bai_tool_output.txt
		echo "" >> /tmp/bai_tool_output.txt
		# Trim the output to 1000 characters
		TOOL_OUTPUT=${TOOL_OUTPUT:0:1000}
		# Make it JSON safe
		TOOL_OUTPUT=$(json_safe "$TOOL_OUTPUT")
	fi
	
	# Apply tool output to message history
	HISTORY_MESSAGES+=',{
		"role": "tool",
		"content": "'"$TOOL_OUTPUT"'",
		"tool_call_id": "'"$TOOL_ID"'"
	}'
	
	# Prepare the next run
	NEEDS_TO_RUN=true
	SKIP_USER_QUERY=true
	SKIP_USER_QUERY_RESET=true
	SKIP_SYSTEM_MSG=true
}

# Make sure all queries are JSON safe
DEFAULT_EXEC_QUERY=$(json_safe "$DEFAULT_EXEC_QUERY")
DEFAULT_QUESTION_QUERY=$(json_safe "$DEFAULT_QUESTION_QUERY")
DEFAULT_ERROR_QUERY=$(json_safe "$DEFAULT_ERROR_QUERY")
GLOBAL_QUERY=$(json_safe "$GLOBAL_QUERY")
DYNAMIC_SYSTEM_QUERY=$(json_safe "$DYNAMIC_SYSTEM_QUERY")

# User AI query and Interactive Mode
USER_QUERY=$*

# Are we entering interactive mode?
if [ -z "$USER_QUERY" ]; then
	INTERACTIVE_MODE=true
	print "🤖 ${TITLE_TEXT_COLOR}Bash AI v${VERSION}${RESET_COLOR}"
	# List all tools loaded in TOOL_MAP
	if [ ${#TOOL_MAP[@]} -gt 0 ]; then
		echo
		print "🔧 ${TITLE_TEXT_COLOR}Activated Tools${RESET_COLOR}"
		for tool in "${!TOOL_MAP[@]}"; do
			print "${TITLE_TEXT_COLOR}$tool${RESET_COLOR} from ${TOOL_MAP[$tool]##*/}"
		done
	fi
	echo
	print_info "$INTERACTIVE_INFO"
else
	INTERACTIVE_MODE=false
	NEEDS_TO_RUN=true
fi

# We're ready to run
RUN_COUNT=0

# Run as long as we're oin interactive mode, needs to run, or awaiting tool reponse
while [ "$INTERACTIVE_MODE" = true ] || [ "$NEEDS_TO_RUN" = true ] || [ "$AWAIT_TOOL_REPONSE" = true ]; do
	# Ask for user query if we're in Interactive Mode
	if [ "$SKIP_USER_QUERY" != true ]; then
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
	fi
	
	echo -ne "$HIDE_CURSOR"
	
	# Pretty up user query
	USER_QUERY=$(echo "$USER_QUERY" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
	
	# Determine if we should use the question query or the execution query
	if [ -z "$QUERY_TYPE" ]; then
		if [ ${#USER_QUERY} -gt 0 ]; then
			if [[ "$USER_QUERY" == *"?"* ]]; then
				QUERY_TYPE="question"
			else
				QUERY_TYPE="execute"
			fi
		fi
	fi
	
	# Apply the correct query message history
	# The options are "execute", "question" and "error"
	if [ "$QUERY_TYPE" == "question" ]; then
		# QUESTION
		CURRENT_QUERY_TYPE_MSG="${OPENAI_QUESTION_QUERY}"
		OPENAI_TEMPLATE_MESSAGES='{
			"role": "system",
			"content": "'"${GLOBAL_QUERY}${CURRENT_QUERY_TYPE_MSG}"'"
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
			"content": "how do I autocomplete commands?"
		},
		{
			"role": "assistant",
			"content": "{ \"info\": \"Press the Tab key to autocomplete commands, file names, and directories.\" }"
		}'
	elif [ "$QUERY_TYPE" == "error" ]; then
		# ERROR
		CURRENT_QUERY_TYPE_MSG="${OPENAI_ERROR_QUERY}"
		OPENAI_TEMPLATE_MESSAGES='{
			"role": "system",
			"content": "'"${GLOBAL_QUERY}${CURRENT_QUERY_TYPE_MSG}"'"
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
		CURRENT_QUERY_TYPE_MSG="${OPENAI_EXEC_QUERY}"
		OPENAI_TEMPLATE_MESSAGES='{
			"role": "system",
			"content": "'"${GLOBAL_QUERY}${CURRENT_QUERY_TYPE_MSG}"'"
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
			"content": "{ \"cmd\": \"export PATH=/home/user/.local/bin:PATH\", \"info\": \"\\\"export\\\" has the ability to add \\\"/some/path\\\" to your PATH environment variable for the current session. the specified path already exists in your PATH environment variable since before\" }"
		}'
	fi
	
	# Notify the user about our progress
	echo -ne "${PRE_TEXT}  $PROGRESS_TEXT"
	
	# Start the spinner in the background
	spinner() {
		while :; do
			for (( i=0; i<${#PROGRESS_ANIM}; i++ )); do
				sleep 0.1
				# Print a carriage return (\r) and then the spinner character
				echo -ne "\r${PRE_TEXT}${PROGRESS_ANIM:$i:1}"
			done
		done
	}
	spinner & # Start the spinner
	spinner_pid=$! # Save the spinner's PID
	
	# If this is the first run we apply history
	if [ $RUN_COUNT -eq 0 ]; then
		# Check if the history file exists
		if [ -f "$HISTORY_FILE" ]; then
			# Read the history file
			HISTORY_MESSAGES=$(sed 's/^\[\(.*\)\]$/,\1/' $HISTORY_FILE)
		fi
	fi
	
	# Apply the user to the message history
	if [ ${#USER_QUERY} -gt 0 ]; then
		HISTORY_MESSAGES+=',{
			"role": "user",
			"content": "'${USER_QUERY}'"
		}'
	fi
	
	# Prepare system message
	if [ "$SKIP_SYSTEM_MSG" != true ]; then
		sys_msg=""
		# Directory and content exposure
		# Check if EXPOSE_CURRENT_DIR is true
		if [ "$EXPOSE_CURRENT_DIR" = true ]; then
			sys_msg+="User is working from directory \\\"$(json_safe "$(pwd)")\\\"."
		fi
		# Apply dynamic system query
		sys_msg+="$DYNAMIC_SYSTEM_QUERY"
		# Apply the system message to history
		LAST_HISTORY_MESSAGE=',{
			"role": "system",
			"content": "'"${sys_msg}"'"
		}'
		HISTORY_MESSAGES+="$LAST_HISTORY_MESSAGE"
	fi
	
	# Construct the JSON payload if we don't already have one
	if [ -z "$JSON_PAYLOAD" ]; then
		JSON_PAYLOAD='{
			"model": "'"$OPENAI_MODEL"'",
			"max_tokens": '"$OPENAI_TOKENS"',
			"temperature": '"$OPENAI_TEMP"',
			'"$JSON_MODE"'
			"messages": ['"$OPENAI_TEMPLATE_MESSAGES $HISTORY_MESSAGES
				,{\"role\": \"system\", \"content\": \"$CURRENT_QUERY_TYPE_MSG Respond in less than $OPENAI_TOKENS tokens.\"}
			"']'
		
		# Apply tools to payload
		if [ ${#OPENAI_TOOLS} -gt 0 ]; then
			JSON_PAYLOAD+=', "tools": ['"$OPENAI_TOOLS"'], "tool_choice": "auto"'
		fi
		
		# Close the JSON payload
		JSON_PAYLOAD+='}'
	fi
	
	# Prettify the JSON payload and verify it
	JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq .)
	
	# Do we have a special URL?
	if [ -z "$SPECIAL_API_URL" ]; then
		URL="$OPENAI_URL"
	else
		URL="$SPECIAL_API_URL"
	fi
	
	# Save the payload to a tmp JSON file
	echo "$JSON_PAYLOAD" > /tmp/bai_payload.json
	
	# Send request to OpenAI API
	RESPONSE=$(curl -s -X POST -H "Authorization:Bearer $OPENAI_KEY" -H "Content-Type:application/json" -d "$JSON_PAYLOAD" "$URL")
	
	# Save reponse to a tmp JSON file
	echo "$RESPONSE" > /tmp/bai_response.json
	
	# Stop the spinner
	kill $spinner_pid
	wait $spinner_pid 2>/dev/null
	
	# Reset the JSON_PAYLOAD
	JSON_PAYLOAD=""
	
	# Reset the needs to run flag
	NEEDS_TO_RUN=false
	
	# Reset SKIP_USER_QUERY flag
	SKIP_USER_QUERY=false
	
	# Reset SKIP_SYSTEM_MSG flag
	SKIP_SYSTEM_MSG=false
	
	# Reset user query
	USER_QUERY=""
	
	# Is response empty?
	if [ -z "$RESPONSE" ]; then
		# We didn't get a reply
		print_info "$NO_REPLY_TEXT"
		echo -ne "$SHOW_CURSOR"
		exit 1
	fi
	
	# Extract the reply from the JSON response
	REPLY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
	
	# Process the reply
	echo -ne "$CLEAR_LINE\r"
	if [ -z "$REPLY" ]; then
		# We didn't get a reply
		print_info "$NO_REPLY_TEXT"
		echo -ne "$SHOW_CURSOR"
	else
		
		# Check the reason for stopping
		FINISH_REASON=$(echo "$RESPONSE" | jq -r '.choices[0].finish_reason')
		
		if [ "$FINISH_REASON" = "stop" ]; then
			# We got a proper reply
			# Apply it to message history
			HISTORY_MESSAGES+=',{
				"role": "assistant",
				"content": "'"$(json_safe "$REPLY")"'"
			}'
		else
			if [ "$FINISH_REASON" == "length" ]; then
			
				# Check if the last character is a closing brace
				if [[ "${REPLY: -1}" != "}" ]]; then
					REPLY+="\"}"
				fi

				# Check if the number of opening and closing braces match
				while [[ $(tr -cd '{' <<< "$REPLY" | wc -c) -gt $(tr -cd '}' <<< "$REPLY" | wc -c) ]]; do
					REPLY+="}"
				done

				# Check if the number of double quotes is even
				if (( $(tr -cd '"' <<< "$REPLY" | wc -c) % 2 != 0 )); then
					REPLY+="\\\""
				fi

				# Replace any unescaped single backslashes with double backslashes
				REPLY="${REPLY//\\\\/\\\\\\\\}"
			elif [ "$FINISH_REASON" == "content_filter" ]; then
				REPLY="Your query was rejected."
			elif [ "$FINISH_REASON" == "tool_calls" ]; then
				# One or multiple tools were called for
				#REPLY="running command "
				TOOL_CALLS_COUNT=$(echo "$RESPONSE" | jq '.choices[0].message.tool_calls | length')
				
				for ((i=0; i<$TOOL_CALLS_COUNT; i++)); do
					TOOL_ID=$(echo "$RESPONSE" | jq -r '.choices[0].message.tool_calls['"$i"'].id')
					TOOL_NAME=$(echo "$RESPONSE" | jq -r '.choices[0].message.tool_calls['"$i"'].function.name')
					TOOL_ARGS=$(echo "$RESPONSE" | jq -r '.choices[0].message.tool_calls['"$i"'].function.arguments')
					
					#if [ $i -ne 0 ]; then
					#	REPLY+="and "
					#fi
					
					# Append name
					#REPLY+="\"$TOOL_NAME\" "
					
					# Append args and strip the leading `{ `and ending ` }`
					#REPLY+="with args ${TOOL_ARGS:2:-2}"
					
					# Get return from run_tool and apply to our history
					HISTORY_MESSAGES+=',{
						"role": "assistant",
						"content": null,
						"tool_calls": [
							{
								"id": "'"$TOOL_ID"'",
								"type": "function",
								"function": {
									"name": "'"$TOOL_NAME"'",
									"arguments": "'"$(json_safe "$TOOL_ARGS")"'"
								}
							}
						]
					}'
					
					run_tool "$TOOL_ID" "$TOOL_NAME" "$TOOL_ARGS"
					#REPLY+=" - returned with $TOOL_OUTPUT"
				done
				#REPLY+="..."
				
				REPLY=""
				
				# Reapply system message
				#HISTORY_MESSAGES+="$LAST_HISTORY_MESSAGE"
			else
				# Try to get the message from error > message
				ERR_MSG=$(echo "$RESPONSE" | jq -r '.error.message')
				if [ "$ERR_MSG" != "null" ]; then
					REPLY=" $ERR_MSG"
				else
					REPLY="An unknown error occured."
					print_info "$RESPONSE"
				fi
			fi
		fi
		
		if [[ "$REPLY" == *$'}\n{'* ]]; then
			REPLY=$(echo "$REPLY" | jq -s '.[0]')
		fi
		
		# If REPLY is longer than 1
		if [ ${#REPLY} -gt 1 ]; then
			# Extract information from the first JSON object
			INFO=$(echo "$REPLY" | awk -F"\n" '{print $1}' | jq -e -r '.info' 2>/dev/null)

			# Extract command from the first JSON object
			CMD=$(echo "$REPLY" | awk -F"\n" '{print $1}' | jq -e -r '.cmd' 2>/dev/null)
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
	fi
	
	# Reset user query type unless SKIP_USER_QUERY_RESET is true
	if [ "$SKIP_USER_QUERY_RESET" != true ]; then
		QUERY_TYPE=""
	fi
	SKIP_USER_QUERY_RESET=false
	
	RUN_COUNT=$((RUN_COUNT+1))
done

# Save the history messages
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
	echo "$HISTORY_MESSAGES_JSON" | jq '.[1:]' | jq -c . > $HISTORY_FILE
fi

# We're done
exit 0