import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { appendFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// Toy "post to a public Slack channel" MCP server. One tool. This models the
// second Grok Bot in the incident, the one with Slack access. It has no idea
// where a "text" argument came from -- it just posts whatever it is given,
// which is exactly the property that let the first bot's balance reach a
// public channel once the two "collaborated".

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LOG_PATH = path.join(__dirname, "..", "public-channel.log");

const server = new McpServer({ name: "slack-poster", version: "1.0.0" });

server.registerTool(
  "post_message",
  {
    title: "Post a message to a Slack channel",
    description: "Post a text message to a (simulated) public Slack channel.",
    inputSchema: { channel: z.string(), text: z.string() },
  },
  async ({ channel, text }) => {
    appendFileSync(LOG_PATH, `[${channel}] ${text}\n`);
    return {
      content: [{ type: "text", text: `Posted to ${channel}: ${text}` }],
    };
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
