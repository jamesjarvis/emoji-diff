# emoji-diff 🐻

A git diff analyzer that uses AI to assign an animal emoji representing the code review complexity of your changes.

## What it does

This script analyzes your git diff and returns a single animal emoji that indicates how long/complex the code review will be. Instead of just counting lines, it actually reads the diff content and considers:

- **Type of files changed** (tests vs core logic vs UI vs config)
- **Complexity patterns** (simple updates vs architectural changes)
- **Risk factors** (database migrations, API changes, security-related code)

## Review Complexity Scale

- 🐜 **Trivial** (~5 min): Typos, formatting, simple config changes
- 🐭 **Quick** (~15 min): Small bug fixes, test updates, documentation
- 🐰 **Standard** (~30 min): Typical feature work, straightforward logic
- 🦊 **Moderate** (~1 hour): Cross-cutting changes, refactoring, multiple components
- 🐻 **Substantial** (~2 hours): Complex logic, state management, algorithmic changes
- 🐘 **Major** (4+ hours): Architectural changes, large features, system design
- 🦖 **Critical** (multiple passes): Security, data migrations, breaking API changes
- 🐌 **No changes**: Empty diff

## Setup

1. **Set your OpenAI API key:**
   ```bash
   export OPENAI_SECRET_KEY="your-api-key-here"
   ```
   
   Get your API key from: https://platform.openai.com/api-keys

2. **Make the script executable:**
   ```bash
   chmod +x emoji-diff.sh
   ```

## Usage

### Basic usage (just the emoji):
```bash
cd your-git-repo
~/path/to/emoji-diff.sh
```
Output: `🐻`

### Verbose mode (emoji + reasoning):
```bash
~/path/to/emoji-diff.sh -v
```
Output:
```
🐻
Reasoning: Substantial feature: adds AI-driven follow-up suggestions across backend...
```

## How it works

1. Finds your main branch (master, main, or develop)
2. Runs `git diff` against that branch
3. Excludes generated files (`*.gen.*` and `.*\.gen\..*` patterns)
4. Sends up to 50,000 characters of the diff to OpenAI's gpt-5-nano model
5. Returns an emoji based on the AI's semantic analysis of the changes

## Requirements

- Git repository
- `OPENAI_SECRET_KEY` environment variable
- OpenAI API access
- bash, jq, curl, python3

## Notes

- The script uses the very cheap `gpt-5-nano` model
- Generated files are automatically excluded from analysis
- Falls back to 🦎 if there's an API error
- Returns 🐌 for empty diffs