# Context Hub Lookup

Search and fetch curated API documentation from Context Hub before writing code.

## Usage

When given a topic or API name: `$ARGUMENTS`

## Instructions

1. If `$ARGUMENTS` is provided, search for it:
   ```bash
   chub search "$ARGUMENTS"
   ```

2. If a matching doc is found, fetch it with the appropriate language flag:
   - For Python backend code: `chub get <id> --lang py`
   - For JavaScript/TypeScript frontend code: `chub get <id> --lang js`

3. Read the fetched documentation carefully.

4. Present a concise summary of the key patterns, gotchas, and correct usage to the user.

5. If no arguments provided, list all available docs:
   ```bash
   chub search --limit 100
   ```

## Examples

- `/chub clerk auth` - Fetch Clerk auth docs
- `/chub gemini` - Fetch Gemini API docs
- `/chub redis` - Fetch Redis docs
- `/chub` - List all available docs
