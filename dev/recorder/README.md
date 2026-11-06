# town-recorder

A development tool for agent-town (Phase 0). It records the Claude Code events agent-town uses (session, prompt, turn, agent, tool, message, and Stop events) to `~/Library/Application Support/agent-town/recorder/<session id>.jsonl`, so the real order, timing and fields can be checked before the real mod is written. Once per session it also POSTs a heartbeat to the agent-town endpoint, if the app or `tools/debug-receiver.py` is running, and times one Haiku classification over the role catalog when the project has `catalog/roles.json`. Every hook passes events on unchanged.
