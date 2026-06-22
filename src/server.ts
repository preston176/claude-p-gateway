import { Hono } from "hono";
import { bearerAuth } from "hono/bearer-auth";
import { runClaude } from "./claude";

const app = new Hono();

const token = process.env.GATEWAY_TOKEN;
if (!token) throw new Error("GATEWAY_TOKEN env var is required");

app.use("/v1/*", bearerAuth({ token }));

app.get("/health", (c) => c.json({ ok: true }));

type AnthropicMessage = { role: "user" | "assistant"; content: string | Array<{ type: string; text?: string }> };

function messagesToPrompt(messages: AnthropicMessage[], system?: string): string {
  const parts: string[] = [];
  if (system) parts.push(`System: ${system}`);
  for (const m of messages) {
    const text = typeof m.content === "string"
      ? m.content
      : m.content.map((b) => b.text ?? "").join("\n");
    parts.push(`${m.role === "user" ? "Human" : "Assistant"}: ${text}`);
  }
  return parts.join("\n\n");
}

app.post("/v1/messages", async (c) => {
  const body = await c.req.json<{ model?: string; system?: string; messages: AnthropicMessage[] }>();
  if (!body?.messages?.length) return c.json({ error: "messages required" }, 400);

  const prompt = messagesToPrompt(body.messages, body.system);
  const { text, raw } = await runClaude(prompt, { model: body.model });

  return c.json({
    id: `msg_${crypto.randomUUID()}`,
    type: "message",
    role: "assistant",
    model: body.model ?? "claude",
    content: [{ type: "text", text }],
    stop_reason: "end_turn",
    usage: { input_tokens: 0, output_tokens: 0 },
    _meta: { source: "claude-p-gateway", raw },
  });
});

export default app;
