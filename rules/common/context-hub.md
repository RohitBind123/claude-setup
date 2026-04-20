# Context Hub — API Documentation Lookup

## Rule: Always Check Context Hub Before Using External APIs

Before writing or modifying code that integrates with an external API or SDK, run `chub search` to check if curated documentation exists. If it does, fetch and read it BEFORE writing code.

## When to Use

Trigger a `chub get` lookup when working with ANY of these (or similar external APIs):

| API/SDK | chub ID | Language |
|---------|---------|----------|
| Clerk Auth | `clerk/auth` | `--lang py` (backend), `--lang js` (frontend) |
| Gemini AI | `gemini/genai` | `--lang py` |
| Gemini Deep Research | `gemini/deep-research` | `--lang py` |
| ChromaDB | `chromadb/embeddings-db` | `--lang py` |
| MongoDB | `mongodb/atlas` | `--lang js` |
| Redis | `redis/key-value` | `--lang py` |
| Stripe | `stripe/payments` | `--lang js` |

## How to Use

```bash
# Search for docs on a topic
chub search "clerk auth"

# Fetch Python docs for an API
chub get clerk/auth --lang py

# Fetch JS docs for frontend
chub get clerk/auth --lang js

# Fetch full documentation (all files)
chub get gemini/genai --lang py --full
```

## Workflow

1. Detect that the task involves an external API/SDK
2. Run `chub search <api-name>` to check availability
3. If found, run `chub get <id> --lang <py|js>` and read the output
4. Use the documented patterns, NOT hallucinated API calls
5. If the docs are wrong or incomplete, run `chub annotate <id> "note"` to save the finding

## Do NOT Skip This When

- Writing new API integration code
- Debugging API-related errors (the docs may have gotchas)
- Upgrading or migrating an SDK version
- Unsure about correct method signatures, parameters, or patterns
