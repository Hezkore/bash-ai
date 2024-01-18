# Bash AI (bai)

Bash AI (bai) is a bash shell script that acts as an AI assistant, allowing you to use natural language for any terminal-based task. It provides command suggestions based on your input and allows you to execute the suggested commands if desired.

## Features

- Natural language interface: Communicate with the terminal using everyday language.
- Command suggestions: Get intelligent command suggestions based on your input.
- Command information: Provides details about the suggested command.
- Execute commands: Choose to execute the suggested commands directly from bai.

## Installation

1. Clone the repository:

	```bash
	git clone https://github.com/hezkore/bash-ai.git
	```
2. Make the script executable:

	```bash
	chmod +x bai.sh
	```

3. Execute bai:

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

Run `./bai.sh your request` and Bash AI will return a suggestion for your request.\
For example:

```
./bai.sh create a new directory with a name of your choice, then create a text file inside it
```

## Prerequisites

- [OpenAI account and API key](https://platform.openai.com/apps)
- [Curl](https://curl.se/download.html)
- [JQ](https://stedolan.github.io/jq/download/)

## License

This project is licensed under the GNU General Public License v3.0 (GPLv3). This means you are free to use, modify, and distribute the original or modified content. However, if you modify the code, you are required to distribute your changes under the same license, thereby contributing your changes back to the community.

For more information, please see the [GPLv3 FAQ](https://www.gnu.org/licenses/gpl-faq.html).