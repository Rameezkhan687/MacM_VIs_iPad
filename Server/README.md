# MoleculePad Copilot server

This optional edge worker turns open-ended language into the same allow-listed commands used by MoleculePad’s on-device Copilot. The OpenAI key stays on the server. Both the worker and the iPad independently reject unknown commands.

## Deploy

1. Copy `wrangler.toml.example` to `wrangler.toml`.
2. Configure `OPENAI_API_KEY` and a long random `MOLECULEPAD_ACCESS_TOKEN` as encrypted deployment secrets.
3. Deploy the worker and confirm `GET /health` returns protocol version 1.
4. In MoleculePad, open **Automation & Plug-ins**, enter `https://your-worker.example/api/copilot` and the access token, then save. The token is stored in the iPad Keychain.

The worker uses the OpenAI Responses API with strict JSON-schema output, `store: false`, a privacy-preserving safety identifier, request-size limits, and a command allow-list. Change `OPENAI_MODEL` in deployment configuration to select another Structured Outputs-capable model.

Official references: [Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create) and [model guidance](https://developers.openai.com/api/docs/guides/latest-model).
