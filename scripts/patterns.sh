# shellcheck shell=sh disable=SC2034
# git-attribution-guard: built-in AI / bot identity patterns.
#
# This is the ONLY place the built-in list lives. Add a line to extend it.
#
# Format: one POSIX extended regular expression (ERE) per line.
#   - Matching is case-insensitive: write patterns in lower case.
#   - They are matched against the trailer value (name AND <email>) and
#     against commit author / committer identities.
#   - "\b" is a word boundary: it matches any character that is not
#     [a-z0-9], or the start/end of the text. Use it for short words that
#     could appear inside other words (e.g. "aider" vs "raider").
#   - Lines starting with "#" and blank lines are ignored.
#
# Users can add patterns without editing this file:
#   git config --global --add attribution.extraPatterns '\bmy-bot\b'
#
# Emails listed in attribution.allow always win over these patterns, so a
# human who happens to be called "Claude" can still be allowed explicitly.

GAG_BUILTIN_PATTERNS='
# Anthropic / Claude
\bclaude\b
anthropic\.com
# GitHub Copilot
\bcopilot\b
github-copilot
# Cursor
\bcursor\b
cursoragent
# OpenAI
\bcodex\b
\bchatgpt\b
openai\.com
# Google
\bgemini\b
google-labs
# Aider
\baider\b
aider\.chat
# Devin (Cognition)
\bdevin-ai
devin\.ai
cognition\.ai
# Windsurf / Codeium
\bwindsurf\b
\bcodeium\b
# Amazon Q
\bamazon[ -]?q\b
# Tabnine
\btabnine\b
# Generic bots
\[bot\]
bot@users\.noreply\.github\.com
'
