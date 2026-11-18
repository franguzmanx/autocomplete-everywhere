import { serve } from "@hono/node-server";

import { app } from "./index.js";

serve({ fetch: app.fetch, port: 3001 }, ({ port }) => {
  process.stderr.write(`Autocomplete Everywhere API listening on http://127.0.0.1:${port}\n`);
});
