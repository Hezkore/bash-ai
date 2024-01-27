# Bash AI

Bash AI _(bai)_ is an advanced Bash shell script functioning as an AI-powered terminal assistant, inspired by [Your AI _(yai)_](https://github.com/ekkinox/yai).\
Leveraging the newest OpenAI's capabilities, it allows you to ask questions and perform terminal-based tasks using natural language. It provides answers and command suggestions based on your input and allows you to execute or edit the suggested commands if desired.

Bash AI is not only powerful out of the box, but also expandable!\
With its plugin architecture, you can easily add your own tools, thereby empowering Bash AI to accomplish even more, and extending its functionality beyond its original capabilities.

## Features

Bash AI offers the following features:

- **100% Shell Script**\
	No need to install anything. Just run it!
	
- **Plugins!**\
	Extend Bash AI's functionality by adding plugins known as "tools".

- **Natural Language Interface**\
	Communicate with the terminal using everyday language.
	
- **Question Answering**\
	Get answers to all your terminal questions by ending your request with a question mark.

- **Command Suggestions**\
	Receive intelligent command suggestions based on your input.

- **Command Information**\
	Get detailed information about the suggested commands.
	
- **Distribution Awareness**\
	Get answers and commands that are compatible with, and related to, your specific Linux distribution.

- **Command Execution**\
	Choose to execute the suggested commands directly from Bash AI.

- **Command Editing**\
	Edit the suggested commands before execution.

- **Error Examination**\
	Examine the error messages generated by the suggested commands and attempt to fix them.

- **Persistent Memory**\
	Remembers your previous requests and uses them to improve future suggestions.

- **Directory Awareness**\
	Automatically detects and uses the current directory when executing commands.

- **Locale Awareness**\
	Automatically detects your system's locale and uses it to provide localized responses.

- **Vim Awareness**\
	Automatically detects if you are using Vim and provides Vim-specific suggestions.

## Setup

* To setup Bash AI quickly, you can run the following command:

```bash
curl -sS https://raw.githubusercontent.com/hezkore/bash-ai/main/install.sh | bash
```

> [!WARNING]
> Never run unknown scripts without reviewing them for safety. Read the install script [here](https://raw.githubusercontent.com/hezkore/bash-ai/main/install.sh).

* Run `bai` to start Bash AI.

<details>
<summary><b>Manual Setup</b></summary>

1. Clone or download the repository:

	```bash
	git clone https://github.com/hezkore/bash-ai.git
	```
2. Make the script executable:

	```bash
	chmod +x bai.sh
	```

3. Execute Bash AI:

	```bash
	./bai.sh
	```

*  _(Optional)_ For convenience, you can create a shortcut to the `bai.sh` script. There are two ways to do this:

	* Create a symbolic link in `/usr/local/bin`. This will allow you to run the script from anywhere, without having to type the full path. Replace `path/to/bai.sh` with the actual path to the `bai.sh` script:

		```bash
		ln -s path/to/bai.sh /usr/local/bin/bai
		```

	* Alternatively, you can create an alias for the `bai.sh` script in your `.bashrc` file. This will also allow you to execute the script using the `bai` command, reducing the need for typing the full path to the script each time. Replace `path/to/bai.sh` with the actual path to the `bai.sh` script:

		```conf
		alias bai='path/to/bai.sh'
		```

</details>

## Configuration

On the first run, a configuration file named `bai.cfg` will be created in your `~/.config` directory.\

> [!IMPORTANT]
> Always remove `bai.cfg` before updating Bash AI to avoid compatibility issues.

You must provide a [OpenAI API key](https://platform.openai.com/api-keys) in the `key=` field of this file. The [OpenAI API key](https://platform.openai.com/api-keys) can be obtained from your [OpenAI account](https://platform.openai.com/api-keys).

> [!CAUTION]
> Keeping the key in a plain text file is dangerous, and it is your responsibility to keep it secure.

You can also change the [GPT model](https://platform.openai.com/docs/models), [temperature](https://platform.openai.com/docs/api-reference/chat/create#chat-create-temperature) and many other things in this file.

## Usage

Bash AI operates in two modes: Interactive Mode and Command Mode.

To enter Interactive Mode, you simply run `bai` without any request. This allows you to continuously interact with Bash AI without needing to re-run the command.

In Command Mode, you run `bai` followed by your request, like so: `bai your request here`

Example usage:

```
bai create a new directory with a name of your choice, then create a text file inside it
```

You can also ask questions  by ending your request with a question mark:
```
bai what is the current time?
```

## Plugins and tools

Plugins are OpenAI tools that expand Bash AI's functionality, but they are not included in the default Bash AI setup.\
All tools should be placed in your `~/.bai_tools` directory.\
You can see which tools are currently installed by running `bai`, and Bash AI will list them for you.

Tools are nothing more than a shell script with a `init` and `execute` function.\
You can find examples and available tools in the [tools folder](https://github.com/Hezkore/bash-ai/tree/main/tools).\
Feel free to move them to your `~/.bai_tools` directory to enable them!

## Known Issues

- In Command Mode, avoid using single quotes in your requests.\
	For instance, the command `bai what's the current time?` will not work. However, both `bai "what's the current time?"` and `bai what is the current time?` will execute successfully.\
	Please note that this issue is specific to the terminal, and does not occur in Interactive Mode.

## Prerequisites

- [OpenAI account and API key](https://platform.openai.com/apps)
- [curl](https://curl.se/download.html)
- [jq](https://stedolan.github.io/jq/download/)