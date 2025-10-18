# tesst-bot

This repository contains the Debian "Telegram Mail Pipe" bot that forwards local system mail (root, cron, errors) to a Telegram chat via the Bot API. The packaging script `make-telegram-mail-deb.sh` builds a `.deb` that installs the pipe script, configures Postfix aliases, and guides setup interactively.

The code originates from the [ludini17/telegram-mail-pipe](https://github.com/ludini17/telegram-mail-pipe) project and remains available under the Creative Commons Attribution-NonCommercial 4.0 International License (see `LICENSE.md`). The detailed usage guide from the upstream project is preserved in `README.mailbot.md`.
