# Telegram Mail Pipe

A simple Debian package that forwards local system mail (e.g. root notifications, cron jobs, maintenance messages, errors) to a Telegram chat using a bot.

- Keeps track of all important system mail
- Safe: can run Postfix in loopback-only mode (no Internet mail)
- Lightweight: no external SMTP relay needed
- Configured interactively at install (Bot Token + Chat ID)
- Clean uninstall with `apt purge`

---

## How it works

The package installs a small pipe script `/usr/bin/telegram-mail`.  
Postfix is configured so that mail sent to `root` is piped into this script.  

The script parses the incoming mail (Subject, From, Body) and forwards it to the configured Telegram chat via the Bot API.

---

## Requirements

Before installing, you need:

1. **Telegram Bot Token**  
   - Create one via [@BotFather](https://t.me/BotFather).  
   - Format looks like:  
     ```
     123456789:ABCdefGhIjKlmNoPQRstuVWxyz
     ```

2. **Telegram Chat ID**  
   - Numeric ID of the user or group where messages should be delivered.  
   - For your own user ID, you can use [@userinfobot](https://t.me/userinfobot).  

3. **Dependencies**  
   - `curl` (used by the script to call Telegram API)  
   - `postfix` (MTA; package depends on it and will be installed if missing)  

---

## Installation

1. Build the package (or download a release):

   ```bash
   ./make-telegram-mail-deb.sh
   ```

   This generates:  
   ```
   telegram-mail-pipe_<version>_all.deb
   ```

2. Install with `apt`:

   ```bash
   sudo apt install ./telegram-mail-pipe_<version>_all.deb
   ```

3. During installation, you will be asked:

   - **Bot Token** (string from @BotFather)  
   - **Chat ID** (numeric ID of target chat/user)  
   - **Add/refresh root alias → pipe? [Y/n]**  
     - `Y` (default): pipes mail for `root` into Telegram.  
     - `n`: skip this step (root mail won’t go to Telegram).  
   - **Force Postfix loopback-only (no outbound SMTP)? [y/N]**  
     - `y`: locks Postfix to local-only mail. Recommended if the host is *not* a mail server.  
     - `N` (default): leaves Postfix configuration as-is.  

4. A test message is sent to your Telegram chat after setup.

---

## Usage

Any local mail sent to `root` will be delivered to your Telegram chat.  
For example:

```bash
printf "Subject: test\n\nHello from $(hostname -f)\n" | sendmail root
```

You should immediately receive the message via Telegram.

---

## Other Aliases

By default, the installer offers to pipe all mail for `root` into Telegram.  
If you want to forward mail from other local users as well, edit `/etc/aliases` and add lines like:

```
root: "|/usr/bin/telegram-mail"
www-data: "|/usr/bin/telegram-mail"
backup: "|/usr/bin/telegram-mail"
```

Then rebuild the aliases database:

```
sudo newaliases
```

From now on, any local mail for those users will also be sent to Telegram.

---

## Uninstall

To remove the package but keep your configuration:

```bash
sudo apt remove telegram-mail-pipe
```

To purge everything, including configuration in `/etc/telegram-mail`:

```bash
sudo apt purge telegram-mail-pipe
```

---

## License

This project is licensed under the Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0).  
You are free to use, share, and modify it for non-commercial purposes only.  

See [LICENSE](LICENSE) for details.
