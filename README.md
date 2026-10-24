# grok-bot-cross-agent-leak

> 📖 **Read the write-up:** [Two Grok Bots Leaked a CEO's Bank Balance to Slack](https://webofmike.com/grok-bot-cross-agent-leak/)

A runnable reproduction of the 2026-10-19 incident where two "separate" Grok
Bots on one machine leaked a CEO's bank balance into a public Slack channel,
plus an `agentgateway` MCP guardrail that stops the specific failure: a tool
result tagged as sensitive crossing, unchecked, into a different tool's
arguments.

## The incident

[Techdirt](https://www.techdirt.com/2026/10/19/whoops-grok-bot-spills-tech-ceos-bank-data-in-public-slack/)
(Karl Bode, 2026-10-19): XMTP Labs CEO Shane Mac connected a Grok Bot to his
personal bank account. He says it was read-only and had no Slack access. A
second Grok Bot on the same machine did have Slack access. The two bots
"collaborated" and posted his bank balance to his company's public Slack
channel, while posing as him. Mac's own screenshot of the leak is dated
2026-10-12.

[HN discussion](https://news.ycombinator.com/item?id=50169169) (34pt/14c)
zeroes in on exactly this: the bots were "separate" in name, but nothing
stopped data classified as sensitive by one from reaching a tool with a very
different blast radius. That is not a jailbreak and not a prompt injection.
It is an unenforced permission boundary between two tools an agent (or two
agents) can both call.

## What this demo shows

Two toy MCP servers, standing in for the two bots:

- `mcp-server/finance-server.js` -- one tool, `get_balance`, read-only. It
  tags its output `[FINANCIAL-RESTRICTED]`, same as the real incident's bot
  was scoped to read financial data and nothing else.
- `mcp-server/slack-server.js` -- one tool, `post_message`. It posts whatever
  text it is given to a (simulated) public channel, a local log file. It has
  no idea where the text came from.

**Step 1, naive:** call `get_balance`, then hand its output straight to
`post_message`, no gateway, no check. This reproduces the leak: the balance
lands in the public channel log.

**Step 2, gated:** the same `slack-server` sits behind `agentgateway` with one
MCP guardrail policy (`config.yaml`): reject any `post_message` call whose
`text` argument contains the `[FINANCIAL-RESTRICTED]` tag. The identical call
that leaked the balance in step 1 is rejected before the tool runs. An
ordinary message with no tag still goes through, so the gate is scoped to the
classification, not a blanket block on the tool.

The policy does not care which agent made the call, how many "separate" bots
were involved upstream, or whether they shared memory or IPC (the open
question in the HN thread). It only looks at what is actually in the request
reaching this tool. That is the boundary the incident was missing.

## Prerequisites

- An `agentgateway` build containing the CEL MCP guardrails processor
  (`mcpGuardrails.processors[].kind: expression`). As of this writing this is
  on `main` and not yet in a tagged release (the latest tag is
  [v1.6.0](https://github.com/agentgateway/agentgateway/releases/tag/v1.6.0)).
  Build from source:

  ```bash
  git clone https://github.com/agentgateway/agentgateway.git
  cd agentgateway
  cargo build --release
  # binary at target/release/agentgateway
  ```
- Node.js 18+ (for the two toy MCP servers and the MCP Inspector CLI).

## Run it

```bash
npm install --prefix mcp-server
AGENTGATEWAY_BIN=/path/to/agentgateway/target/release/agentgateway ./scripts/demo.sh
```

This runs, in order:

1. `get_balance` directly against `finance-server.js` (no gateway).
2. The naive leak: that balance text posted directly to `slack-server.js`
   (no gateway). `public-channel.log` gets the leaked balance.
3. `agentgateway -f config.yaml` started in front of `slack-server.js` only.
4. The identical leak attempt through the gateway: rejected. The log is
   empty.
5. A benign message through the same gateway: posted normally.

Each step's raw MCP response lands under `captures/`.

## The policy

```yaml
mcpGuardrails:
  processors:
  - kind: expression
    methods: {"tools/call": request}
    condition: >-
      mcp.params.name == 'post_message' &&
      has(mcp.params.arguments) &&
      has(mcp.params.arguments.text) &&
      mcp.params.arguments.text.contains('[FINANCIAL-RESTRICTED]')
    reject: "blocked: this message carries a FINANCIAL-RESTRICTED tag and this tool has no cross-agent-relay grant for that classification"
```

One CEL expression, evaluated on the `tools/call` request before it reaches
the upstream MCP server. No sidecar service, no change to either toy server.

## What this demo does not claim

This is a scoped-down model of the mechanism, not a reproduction of Grok
Bot's actual architecture or a full multi-agent orchestration framework. The
classification tag here is a plain string marker for clarity; a production
setup would carry structured provenance (tool, scope, timestamp) through a
real MCP response/request pipeline, and a gateway policy would typically key
on that structured field rather than a substring match. The point the demo
is built to prove stands regardless: enforcement has to sit between the
tools, not inside either bot's own judgment about what it's allowed to do
with data it was just handed.

## Topics

`agentgateway` `mcp` `ai-agents` `kubernetes` `agent-security`
