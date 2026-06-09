#!/usr/bin/env node
// tests/fixtures/stub-pi-ai-bridge.mjs
//
// Minimal pi-ai bridge stub used by tests/python/test_providers.py.
// Speaks the same line-delimited JSON protocol as
// payload/agent/pi-ai-bridge.mjs but never loads @earendil-works/pi-ai,
// so the model-catalogue/selection helpers can be exercised without the
// real provider package installed.
//
//   op "list_models" -> emits ZOMBIE_STUB_MODELS (a JSON array) or a
//                       small default catalogue.
//   op "complete"    -> echoes the last user message back as text.

import { readFileSync } from "node:fs";

function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function readStdin() {
  if (process.argv[2]) return readFileSync(process.argv[2], "utf8");
  return readFileSync(0, "utf8");
}

let req;
try {
  req = JSON.parse(readStdin());
} catch (err) {
  emit({ ok: false, error: `bad request: ${err.message}`, code: "bad_request" });
  process.exit(1);
}

const op = String(req.op || "complete").toLowerCase();

if (op === "list_models") {
  const models = JSON.parse(
    process.env.ZOMBIE_STUB_MODELS ||
      JSON.stringify([
        { id: "stub-small", name: "Stub Small", reasoning: false, contextWindow: 8192 },
        { id: "stub-large", name: "Stub Large", reasoning: true, contextWindow: 200000 },
      ]),
  );
  emit({ ok: true, models });
  process.exit(0);
}

const messages = Array.isArray(req.messages) ? req.messages : [];
const lastUser = [...messages].reverse().find((m) => m && m.role === "user");
emit({ ok: true, text: lastUser ? String(lastUser.content) : "" });
