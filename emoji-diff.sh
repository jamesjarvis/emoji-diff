#!/bin/bash

set -euo pipefail

# Parse command line arguments
verbose=false
while getopts "v" opt; do
    case $opt in
        v) verbose=true ;;
        \?) echo "Usage: $0 [-v]" >&2; exit 1 ;;
    esac
done

# Check if OpenAI API key is set
if [[ -z "${OPENAI_SECRET_KEY:-}" ]]; then
    echo "Error: OPENAI_SECRET_KEY environment variable is not set" >&2
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "Error: Not in a git repository" >&2
    exit 1
fi

# Get git diff against main/master branch and filter out *.gen.* files
# Try to find the main branch (master, main, or develop)
main_branch=""
for branch in master main develop; do
    if git show-ref --verify --quiet "refs/heads/$branch" || git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        main_branch="$branch"
        break
    fi
done

# If no main branch found, use HEAD~1 as fallback
if [[ -z "$main_branch" ]]; then
    main_branch="HEAD~1"
fi

# Get git diff using pathspec to exclude *.gen.* files and .*.gen..* files
raw_diff=$(git diff "$main_branch" -- . ':(exclude)*.gen.*' ':(exclude).*\.gen\..*')
if [[ -z "$raw_diff" ]]; then
    echo "🐌"  # No changes emoji
    exit 0
fi

# Truncate diff to 50,000 characters if needed
if [[ ${#raw_diff} -gt 50000 ]]; then
    truncated_diff="${raw_diff:0:50000}"
    diff_content="$truncated_diff

[DIFF TRUNCATED - showing first 50,000 characters of larger change]"
else
    diff_content="$raw_diff"
fi

# Create prompt for OpenAI
prompt="You are a code reviewer estimating how long/complex a PR review will be based on the git diff.

Analyze the following git diff and choose an animal emoji that represents the review complexity.
Consider:
- Type of files changed (tests, core logic, UI, config, migrations)
- Complexity of changes (simple updates vs architectural changes)
- Risk level (data models, API contracts, security, breaking changes)
- Whether changes are mostly additions, deletions, or modifications

Emoji scale for estimated review time/difficulty:
🐜 = Trivial review (5 min): typos, formatting, simple config
🐭 = Quick review (15 min): small bug fixes, test updates, documentation
🐰 = Standard review (30 min): typical feature work, straightforward logic
🦊 = Moderate review (1 hour): cross-cutting changes, refactoring, multiple components
🐻 = Substantial review (2 hours): complex logic, state management, algorithmic changes
🐘 = Major review (4+ hours): architectural changes, large features, system design
🦖 = Critical review (requires multiple passes): security, data migrations, breaking API changes

Git diff to analyze:
\`\`\`diff
$diff_content
\`\`\`

Respond with JSON containing:
1. 'emoji': The single animal emoji representing review complexity
2. 'reasoning': Brief explanation of what makes this review that complexity level (mention specific file types or patterns you noticed)

Format: {\"emoji\": \"🐜\", \"reasoning\": \"Only documentation updates in README files\"}"

# Make API call to OpenAI
api_request_body=$(jq -n \
    --arg model "gpt-5-nano" \
    --arg input "$prompt" \
    '{model: $model, input: $input}')

api_response=$(curl -s "https://api.openai.com/v1/responses" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OPENAI_SECRET_KEY" \
    -d "$api_request_body")

# Extract emoji from response - the API response has a different structure
response_text=$(echo "$api_response" | jq -r '.output[1].content[0].text // empty' 2>/dev/null || echo "")

# Debug: Check if we got an error
error_message=$(echo "$api_response" | jq -r '.error.message // empty' 2>/dev/null || echo "")
if [[ -n "$error_message" ]] && [[ "$verbose" = true ]]; then
    echo "API Error: $error_message" >&2
fi

# Try to parse as JSON first
emoji=$(echo "$response_text" | jq -r '.emoji // empty' 2>/dev/null || echo "")
reasoning=$(echo "$response_text" | jq -r '.reasoning // empty' 2>/dev/null || echo "")

# If that didn't work, look for any emoji in the response text
if [[ -z "$emoji" ]]; then
    emoji=$(echo "$response_text" | python3 -c "
import sys
import re
text = sys.stdin.read()
# Find emoji characters (Unicode ranges for various emoji blocks)
emoji_pattern = r'[\U0001F600-\U0001F64F]|[\U0001F300-\U0001F5FF]|[\U0001F680-\U0001F6FF]|[\U0001F1E0-\U0001F1FF]|[\U0001F900-\U0001F9FF]|[\U0001FA70-\U0001FAFF]'
match = re.search(emoji_pattern, text)
if match:
    print(match.group())
" 2>/dev/null || echo "")
fi

# Output based on verbose flag
if [[ -z "$emoji" ]]; then
    emoji="🦎"  # Fallback emoji
    reasoning="Fallback emoji used due to parsing error"
fi

if [[ "$verbose" = true ]]; then
    echo "$emoji"
    echo "Reasoning: $reasoning"
else
    echo "$emoji"
fi
