# Config templates

Two config formats exist because OpenHands migrated config schemes (V0 → V1).
`install.sh` detects which one your installed CLI uses and writes the real
config into `~/.openhands/`:

- **`agent_settings.json`** — current V1 CLI (has `--override-with-envs`).
- **`config.toml`** — legacy V0 fallback (no `--override-with-envs`).

## The two model-name forms (classic gotcha)

| Where | Model string | Why |
|---|---|---|
| OpenHands/LiteLLM config | `openai/z-ai/glm-5.2` | `openai/` prefix routes via LiteLLM's OpenAI-compatible path |
| Raw NIM API (curl, ping) | `z-ai/glm-5.2` | NIM expects the bare catalog ID |

`.env` stores the **bare** ID (`DEFAULT_MODEL=z-ai/glm-5.2`); scripts add the
`openai/` prefix for OpenHands and use the bare ID for direct NIM calls.

## Vision routing

`delegate.sh -m minimaxai/minimax-m3` swaps the model per call — use M3 for
browser/design tasks (multimodal) and GLM-5.2 for text/code reasoning.
