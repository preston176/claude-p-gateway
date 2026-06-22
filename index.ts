import app from "./src/server";

const port = Number(process.env.PORT ?? 8787);

export default {
  port,
  fetch: app.fetch,
};

console.log(`claude-p-gateway listening on :${port}`);
