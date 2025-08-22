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

# Get git diff using pathspec to exclude *.gen.* files
raw_diff=$(git diff "$main_branch" -- . ':(exclude)*.gen.*')
if [[ -z "$raw_diff" ]]; then
    echo "🐌"  # No changes emoji
    exit 0
fi

# Count lines added and removed
added_lines=$(echo "$raw_diff" | grep -c '^+[^+]' || true)
removed_lines=$(echo "$raw_diff" | grep -c '^-[^-]' || true)
total_changes=$((added_lines + removed_lines))

# If no changes after filtering, return small change emoji
if [[ $total_changes -eq 0 ]]; then
    echo "🐌"
    exit 0
fi

# Create prompt for OpenAI
prompt="Based on the following code change metrics, suggest a single animal emoji that represents the semantic size and complexity of these changes:

- Lines added: $added_lines
- Lines removed: $removed_lines
- Total changes: $total_changes

Please respond with:
1. A single animal emoji that represents the scale (e.g., 🐜 for tiny changes, 🐘 for large changes)
2. A brief reasoning for your choice

Format your response as JSON with 'emoji' and 'reasoning' fields."

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
