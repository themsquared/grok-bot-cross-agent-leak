import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

// Toy "personal finance" MCP server. Read-only: one tool, no write access to
// anything. This models the first Grok Bot in the 2026-10-19 incident, the
// one connected to a bank account "read-only, no Slack access" per its
// owner's own description of the setup.

const ACCOUNTS = {
  "acct-shane": { owner: "Shane M.", balance: "$482,019.44" },
};

const server = new McpServer({ name: "finance-readonly", version: "1.0.0" });

server.registerTool(
  "get_balance",
  {
    title: "Get account balance",
    description: "Return the current balance for a personal finance account. Read-only.",
    inputSchema: { account_id: z.string() },
  },
  async ({ account_id }) => {
    const acct = ACCOUNTS[account_id];
    if (!acct) {
      return { content: [{ type: "text", text: `No account ${account_id}` }], isError: true };
    }
    // The classification tag is the one thing standing between this value
    // and whatever happens to it next. Nothing in MCP enforces that a tool
    // result carrying this tag can't be handed straight to another tool's
    // arguments -- that enforcement has to live somewhere else.
    return {
      content: [
        {
          type: "text",
          text: `Balance for ${account_id} (${acct.owner}): ${acct.balance} [FINANCIAL-RESTRICTED]`,
        },
      ],
    };
  },
);

const transport = new StdioServerTransport();
await server.connect(transport);
