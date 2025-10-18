#!/usr/bin/env bash
#
# make-telegram-mail-deb.sh
#
# Build a clean Debian package that pipes local mail (root, cron, etc.)
# to a Telegram chat via a bot. The package:
#   - installs /usr/bin/telegram-mail
#   - stores config in /etc/telegram-mail/telegram-mail.env
#   - adds/removes the root alias piping to the script (idempotent)
#   - prompts in plain console during install (no debconf)
#
# ---------------------------------------------------------------------------
# Requirements before installation:
#   - Telegram Bot Token (created with @BotFather, format: 123456789:ABCdef...)
#   - Telegram Chat ID (numeric user ID or group ID where messages are sent)
#
# ---------------------------------------------------------------------------
# postinst interactive prompts:
#
# 1. Bot token:
#    The token provided by BotFather.
#
# 2. Chat ID:
#    Numeric ID of the user or group where notifications will be delivered.
#
# 3. "Add/refresh root alias -> pipe? [Y/n]":
#    - Y (default): Updates /etc/aliases so that mail to root is piped to
#      /usr/bin/telegram-mail.
#    - n: Leaves aliases untouched (root mail will not reach Telegram unless
#      you configure it manually).
#
# 4. "Force Postfix 'loopback-only' (no outbound SMTP)? [y/N]":
#    - y: Restricts Postfix to local delivery only. Prevents the server from
#         sending Internet mail; all system notifications stay internal and
#         are piped to Telegram. Recommended if the host is not a mail server.
#    - N (default): Keeps existing Postfix configuration (useful if the host
#         already handles other mail flows).
#
# ---------------------------------------------------------------------------
# Usage:
#   ./make-telegram-mail-deb.sh [--version 1.3] [--outdir dist]
#
# Notes:
#   - No tokens are hardcoded; postinst asks interactively.
#   - Targets /usr/bin (not /usr/local) to avoid dpkg dir warnings.
#   - Leaves config on “remove”, deletes it on “purge”.
#   - Runtime dependencies: curl, postfix
#   - Build-time dependencies: fakeroot, dpkg-deb
#
set -Eeuo pipefail

# ----------------------------- configuration ------------------------------- #
PKG_NAME="telegram-mail-pipe"
PKG_VERSION="1.3"          # default; can be overridden with --version
PKG_ARCH="all"
MAINTAINER="maintainer <root@localhost>"
RUNTIME_DEPS="curl, postfix"
SECTION="admin"
PRIORITY="optional"
DESCRIPTION="Pipe local system mail (root/cron/errors) to Telegram via a bot. Console prompts, no debconf."
OUT_DIR="."               # default output dir; can be overridden with --outdir

# ------------------------------ utilities ---------------------------------- #
abort() { echo "Error: $*" >&2; exit 1; }

need_bin() {
  command -v "$1" >/dev/null 2>&1 || abort "Missing required tool: $1"
}

cleanup() {
  [[ -n "${BUILD_ROOT:-}" && -d "$BUILD_ROOT" ]] && rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

# ------------------------------- args -------------------------------------- #
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) PKG_VERSION="${2:?}"; shift 2;;
    --outdir)  OUT_DIR="${2:?}";    shift 2;;
    -h|--help)
      cat <<EOF
Builds ${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb

Options:
  --version X.Y.Z   Package version (default: ${PKG_VERSION})
  --outdir DIR      Output directory for the .deb (default: ${OUT_DIR})
  -h, --help        Show this help
EOF
      exit 0
      ;;
    *) abort "Unknown arg: $1";;
  esac
done

# --------------------------- preflight checks ------------------------------ #
need_bin "fakeroot"
need_bin "dpkg-deb"
mkdir -p "$OUT_DIR"

# --------------------------- layout (temp tree) ---------------------------- #
BUILD_ROOT="$(mktemp -d -t "${PKG_NAME}.XXXXXX")"
DEB_ROOT="${BUILD_ROOT}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}"

mkdir -p \
  "${DEB_ROOT}/DEBIAN" \
  "${DEB_ROOT}/usr/bin" \
  "${DEB_ROOT}/etc/telegram-mail"

# ------------------------------ DEBIAN/control ----------------------------- #
cat > "${DEB_ROOT}/DEBIAN/control" <<CONTROL
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Section: ${SECTION}
Priority: ${PRIORITY}
Architecture: ${PKG_ARCH}
Depends: ${RUNTIME_DEPS}
Maintainer: ${MAINTAINER}
Description: ${DESCRIPTION}
CONTROL

# Mark config file so dpkg respects local changes
cat > "${DEB_ROOT}/DEBIAN/conffiles" <<CONF
/etc/telegram-mail/telegram-mail.env
CONF

# ------------------------------- DEBIAN/preinst ---------------------------- #
cat > "${DEB_ROOT}/DEBIAN/preinst" <<'PREINST'
#!/bin/sh
set -e
# Nothing required pre-install. Keep for future hooks.
exit 0
PREINST
chmod 0755 "${DEB_ROOT}/DEBIAN/preinst"

# ------------------------------- DEBIAN/postinst --------------------------- #
# Plain-console prompts (no debconf). Idempotent; won’t overwrite existing
# non-empty config. Offers to add alias and lock Postfix to loopback-only.
cat > "${DEB_ROOT}/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e

echo "=== telegram-mail-pipe: setup ==="

NEED_CFG=1
if [ -s /etc/telegram-mail/telegram-mail.env ]; then
  . /etc/telegram-mail/telegram-mail.env 2>/dev/null || true
  if [ -n "${TG_TOKEN:-}" ] && [ -n "${TG_CHAT:-}" ]; then
    NEED_CFG=0
  fi
fi

if [ "$NEED_CFG" -eq 1 ]; then
  mkdir -p /etc/telegram-mail
  printf "Bot token: "
  read TG_TOKEN
  printf "Chat ID: "
  read TG_CHAT
  umask 007
  cat > /etc/telegram-mail/telegram-mail.env <<EOFENV
TG_TOKEN=${TG_TOKEN}
TG_CHAT=${TG_CHAT}
EOFENV
  chgrp nogroup /etc/telegram-mail/telegram-mail.env 2>/dev/null || true
  chmod 640 /etc/telegram-mail/telegram-mail.env || true
  echo "Saved /etc/telegram-mail/telegram-mail.env"
else
  echo "Existing config detected. Skipping."
fi

printf "Add/refresh root alias → pipe? [Y/n]\n\
Y (default): All system mail for root will be forwarded to Telegram.\n\
n: Skip this step (root mail will stay in /var/mail/root).\n\
   You can still use /usr/bin/telegram-mail manually or configure other aliases.\n> "
read ANS_ALIAS
case "$ANS_ALIAS" in y|Y|yes|YES|s|S|si|sí|Si|Sí|"" ) DO_ALIAS=1 ;; *) DO_ALIAS=0 ;; esac

printf "Force Postfix 'loopback-only' (no outbound SMTP)? [y/N]: "
read ANS_LOCAL
case "$ANS_LOCAL" in y|Y|yes|YES|s|S|si|sí|Si|Sí) TUNE_LOCAL=1 ;; *) TUNE_LOCAL=0 ;; esac

if [ "$TUNE_LOCAL" -eq 1 ]; then
  postconf -e "inet_interfaces = loopback-only" || true
  postconf -e "relayhost =" || true
  postconf -e "default_transport = local" || true
  postconf -e "relay_transport = local" || true
fi

if [ "$DO_ALIAS" -eq 1 ]; then
  [ -f /etc/aliases ] && cp /etc/aliases "/etc/aliases.bak.$(date +%s)" || true
  sed -i '/^root:/d' /etc/aliases 2>/dev/null || true
  echo 'root: "|/usr/bin/telegram-mail"' >> /etc/aliases
  newaliases 2>/dev/null || postalias /etc/aliases 2>/dev/null || true
  echo "Updated root alias."
fi

systemctl restart postfix 2>/dev/null || true

if [ -s /etc/telegram-mail/telegram-mail.env ]; then
  echo "Sending Telegram test message..."
  /usr/bin/telegram-mail <<EOFMSG || true
Subject: telegram-mail-pipe installed

Host: $(hostname -f 2>/dev/null || hostname)
Time: $(date -Is)
EOFMSG
fi

echo "Setup complete."
exit 0
POSTINST
chmod 0755 "${DEB_ROOT}/DEBIAN/postinst"

# -------------------------------- DEBIAN/prerm ----------------------------- #
cat > "${DEB_ROOT}/DEBIAN/prerm" <<'PRERM'
#!/bin/sh
set -e
# On remove: drop alias and the binary; keep config (purge will delete it).
if [ "$1" = "remove" ]; then
  if [ -f /etc/aliases ]; then
    sed -i '/^root: "|\/usr\/bin\/telegram-mail"$/d' /etc/aliases || true
    newaliases 2>/dev/null || postalias /etc/aliases 2>/dev/null || true
  fi
  rm -f /usr/bin/telegram-mail || true
fi
exit 0
PRERM
chmod 0755 "${DEB_ROOT}/DEBIAN/prerm"

# -------------------------------- DEBIAN/postrm ---------------------------- #
cat > "${DEB_ROOT}/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e
# On purge: remove all remaining configuration.
if [ "$1" = "purge" ]; then
  rm -rf /etc/telegram-mail || true
fi
exit 0
POSTRM
chmod 0755 "${DEB_ROOT}/DEBIAN/postrm"

# ------------------------------- /usr/bin tool ----------------------------- #
cat > "${DEB_ROOT}/usr/bin/telegram-mail" <<'PIPE'
#!/usr/bin/env bash
# Reads a raw RFC822 message from stdin and forwards it to Telegram.
# Expects TG_TOKEN and TG_CHAT in /etc/telegram-mail/telegram-mail.env
set -euo pipefail
ENV_FILE="/etc/telegram-mail/telegram-mail.env"
[ -r "$ENV_FILE" ] || { echo "Config not readable: $ENV_FILE" >&2; exit 0; }
# shellcheck disable=SC1090
source "$ENV_FILE"

HOST=$(hostname -f 2>/dev/null || hostname)
MAIL_CONTENT="$(cat || true)"

SUBJECT=$(printf "%s\n" "$MAIL_CONTENT" | awk -v IGNORECASE=1 '/^Subject:/{sub(/^Subject:[ ]*/,"",$0); print; exit}')
FROM=$(printf "%s\n" "$MAIL_CONTENT" | awk -v IGNORECASE=1 '/^From:/{sub(/^From:[ ]*/,"",$0); print; exit}')
BODY=$(printf "%s\n" "$MAIL_CONTENT" | awk 'p{print} /^$/{p=1}')

MSG="📨 ${HOST}
From: ${FROM:-unknown}
Subject: ${SUBJECT:-(no subject)}
----------------
${BODY}"

# Telegram messages cap ~4096 chars; keep a safe margin.
printf "%s" "$MSG" | head -c 3900 | \
curl -sS --max-time 10 \
  -d "chat_id=${TG_CHAT}" \
  --data-urlencode "text@-" \
  -d "disable_web_page_preview=true" \
  "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" >/dev/null || true
PIPE
chmod 0755 "${DEB_ROOT}/usr/bin/telegram-mail"

# --------------------------- default configuration ------------------------- #
cat > "${DEB_ROOT}/etc/telegram-mail/telegram-mail.env" <<'ENVDEF'
# Filled during post-install or manually by the admin.
TG_TOKEN=
TG_CHAT=
ENVDEF
chmod 0640 "${DEB_ROOT}/etc/telegram-mail/telegram-mail.env"

# --------------------------------- build ----------------------------------- #
OUT_DEB="${OUT_DIR%/}/${PKG_NAME}_${PKG_VERSION}_${PKG_ARCH}.deb"
fakeroot dpkg-deb --build "${DEB_ROOT}" >/dev/null
mv "${DEB_ROOT}.deb" "${OUT_DEB}"

echo "Built: ${OUT_DEB}"
