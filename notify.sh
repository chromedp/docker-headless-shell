#!/bin/bash

SRC=$(realpath "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)")
. "$SRC/lib.sh"

UNIT=headless-shell.service
WEBHOOK_FILE=$HOME/.config/headless-shell/discord-webhook
LINES=15

DESC='Post a message to a Discord webhook that a user unit failed, including the
tail of its journal. Run by headless-shell-failure.service via OnFailure=.'
OPTS=(
  'unit|UNIT|val|name|user unit to report on'
  'webhook-file|WEBHOOK_FILE|val|file|file containing the Discord webhook URL'
  'lines|LINES|val|n|journal lines to include'
)
parse_opts "$@"

set -e

need curl jq journalctl
[ -r "$WEBHOOK_FILE" ] || die "$WEBHOOK_FILE is not readable"

# keep the whole message under Discord's 2000 character limit
LOG=$(journalctl --user -u "$UNIT" --no-pager -n "$LINES" -o cat |cut -c1-200)
LOG=${LOG: -1500}
MSG=$(printf ':x: **%s** failed on `%s` (%s)\n```\n%s\n```' \
  "$UNIT" "$(hostname)" "$(date '+%a %b %-d %H:%M %Z')" "$LOG")

# the webhook URL is a secret: read it from a file, and pass it to curl on
# stdin so that it does not show up in the process list
printf 'url = "%s"\n' "$(< "$WEBHOOK_FILE")" \
  |curl --silent --show-error --fail \
    --config - \
    --header 'Content-Type: application/json' \
    --data @<(jq -n --arg content "$MSG" '{content: $content, allowed_mentions: {parse: []}}')
