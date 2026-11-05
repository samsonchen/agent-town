# town-recorder

A development tool for claude-town (Phase 0). It records the Claude Code events claude-town uses (session, prompt, turn, agent, tool, message, and Stop events) to `~/Library/Application Support/claude-town/recorder/<session id>.jsonl`, so the real order, timing and fields can be checked before the real mod is written. Once per session it also POSTs a heartbeat to the claude-town endpoint, if the app or `tools/debug-receiver.py` is running, and times one Haiku classification over the role catalog when the project has `catalog/roles.json`. Every hook passes events on unchanged.
