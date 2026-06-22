import { $ } from "bun";

export type ClaudeResult = {
  text: string;
  raw: unknown;
};

export async function runClaude(prompt: string, opts?: { model?: string; cwd?: string }): Promise<ClaudeResult> {
  const args = ["-p", prompt, "--output-format", "json"];
  if (opts?.model) args.push("--model", opts.model);

  const proc = Bun.spawn(["claude", ...args], {
    cwd: opts?.cwd ?? process.cwd(),
    stdout: "pipe",
    stderr: "pipe",
  });

  const [stdout, stderr, exit] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  if (exit !== 0) {
    throw new Error(`claude exited ${exit}: ${stderr || stdout}`);
  }

  const raw = JSON.parse(stdout);
  const text = typeof raw?.result === "string" ? raw.result : JSON.stringify(raw);
  return { text, raw };
}
