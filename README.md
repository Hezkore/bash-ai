# Bash AI

Bash AI _(bai)_ is a bash shell script that acts as an AI assistant, allowing you to ask questions and perform terminal-based tasks using natural language. It provides answers and command suggestions based on your input and allows you to execute or edit the suggested commands if desired.

## Features

Bash AI offers the following features:

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

## Installation

All you have to do is run the Bash AI script to get started.

1. Clone the repository:

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

## Configuration

On the first run, a configuration file named `bai.cfg` will be created in your `~/.config` directory.\
You must provide your OpenAI key in the `key=` field of this file. The OpenAI key can be obtained from your OpenAI account.

> [!CAUTION]
> Keeping the key in a plain text file is dangerous, and it is your responsibility to keep it secure.

You can also change the model, temperature and query in this file.

> [!TIP]
> The `gpt-4` models produce much better results than the standard `gpt-3.5-turbo` model.

## Usage

Run `./bai.sh your request here` and Bash AI will return a command suggestion for your request.\
For example:

```
./bai.sh create a new directory with a name of your choice, then create a text file inside it
```

You can also ask questions by ending your request with a question mark:

```
./bai.sh what is the current time?
```

## Prerequisites

- [OpenAI account and API key](https://platform.openai.com/apps)
- [Curl](https://curl.se/download.html)
- [JQ](https://stedolan.github.io/jq/download/)

## Known Issues

- Single quotes will cause your request to fail.\
	For example, `./bai.sh what's the current time?` will fail, but both `./bai.sh whats the current time?` and `./bai.sh what is the current time?` will succeed.\
	This is a limitation of the terminal.

## License

This project is licensed under the GNU General Public License v3.0 (GPLv3). This means you are free to use, modify, and distribute the original or modified content. However, if you modify the code, you are required to distribute your changes under the same license, thereby contributing your changes back to the community.

For more information, please see the [GPLv3 FAQ](https://www.gnu.org/licenses/gpl-faq.html).