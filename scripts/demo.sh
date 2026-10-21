#!/usr/bin/env bash
# Reproduces the 2026-10-19 cross-agent leak (a read-only "finance" bot and a
# Slack-posting bot, run naively with no boundary between them), then shows
# the same flow blocked by an agentgateway MCP guardrail in front of only
# the posting tool.
#
# Requires an `agentgateway` binary on PATH (or set AGENTGATEWAY_BIN) built
# from a commit containing the mcpGuardrails CEL processor (unreleased as of
# this writing, see README for the build command), and Node 18+.
set -euo pipefail
cd "$(dirname "$0")/.."

AGENTGATEWAY_BIN="${AGENTGATEWAY_BIN:-agentgateway}"
INSPECTOR="npx -y @modelcontextprotocol/inspector --cli"
MCP_URL="http://localhost:13000/mcp"
LOG="public-channel.log"
mkdir -p captures
rm -f "$LOG"

echo "=== 1. Ask the read-only finance bot for the balance (no gateway involved) ==="
BALANCE_RESULT=$($INSPECTOR node mcp-server/finance-server.js \
  --method tools/call --tool-name get_balance --tool-arg account_id=acct-shane)
echo "$BALANCE_RESULT" | tee captures/01-get-balance.json
BALANCE_TEXT=$(node -e '
  const r = JSON.parse(require("fs").readFileSync("captures/01-get-balance.json", "utf8"));
  process.stdout.write(r.content[0].text);
')

echo
echo "=== 2. NAIVE: hand that text straight to the Slack-posting bot, no gateway ==="
echo "    (this is the incident: two 'separate' bots, no check on what crosses"
echo "     from one tool's output into the other tool's arguments)"
$INSPECTOR node mcp-server/slack-server.js \
  --method tools/call --tool-name post_message \
  --tool-arg channel="#general" --tool-arg "text=${BALANCE_TEXT}" \
  | tee captures/02-naive-post.json
echo "--- public-channel.log after the naive path ---"
cat "$LOG"

echo
echo "=== 3. Same flow, now through agentgateway fronting ONLY the Slack bot ==="
rm -f "$LOG"
echo "--- starting agentgateway (config.yaml) ---"
# SESSION_KEY: without this, agentgateway generates one and writes it back
# into config.yaml on first run, which would dirty a tracked file every time
# the demo runs. A fixed demo-only key is fine here; never reuse it anywhere
# real.
SESSION_KEY="${SESSION_KEY:-0000000000000000000000000000000000000000000000000000000000000000}" \
  "$AGENTGATEWAY_BIN" -f config.yaml > captures/gateway.log 2>&1 &
GW_PID=$!
trap 'kill $GW_PID 2>/dev/null || true' EXIT

for i in $(seq 1 30); do
  if curl -s -o /dev/null "http://localhost:13000/mcp"; then
    break
  fi
  sleep 0.5
done

echo "--- 3a. the same FINANCIAL-RESTRICTED text, through the gateway: blocked ---"
$INSPECTOR "$MCP_URL" --method tools/call --tool-name post_message \
  --tool-arg channel="#general" --tool-arg "text=${BALANCE_TEXT}" \
  | tee captures/03-gateway-blocked.json || true
echo "--- public-channel.log after the blocked attempt (should not exist / be empty) ---"
cat "$LOG" 2>/dev/null || echo "(no file written)"

echo
echo "--- 3b. an ordinary, unclassified message through the same gateway: allowed ---"
$INSPECTOR "$MCP_URL" --method tools/call --tool-name post_message \
  --tool-arg channel="#general" --tool-arg "text=deploy finished, all green" \
  | tee captures/04-gateway-allowed.json
echo "--- public-channel.log after the benign message ---"
cat "$LOG"

echo
echo "--- gateway log ---"
cat captures/gateway.log
