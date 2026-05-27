---
name: session-handoff
description: Write a concise, agent-facing Markdown handoff for a fresh coding-agent session. Use when the user asks to hand off, summarize, condense, preserve, export, resume, or transfer important context from the current session into a new agent session.
---

# Session Handoff

Create a Markdown handoff document that lets a fresh agent session continue the work without inherited chat context.

If the user names a file or path, write there. Otherwise write `HANDOFF.md` in the current workspace.

Use the current conversation context and light repo inspection. Do not read Codex session JSONL files unless the user explicitly asks for forensic reconstruction.

Write the handoff naturally. Do not turn it into a transcript or force a rigid template. Include whatever is actually useful for the next agent, especially:

- the current goal and next step
- current repo state, branch, commits, and uncommitted work
- active architecture and important design boundaries
- settled decisions and user corrections
- failed or abandoned paths that should not be reopened casually
- important files, commands, tests, diagnostics, docs, and config
- how the project is built, launched, tested, debugged, or otherwise operated, especially when the team uses a wrapper script or non-obvious command instead of the default tool command
- verification status, risks, open questions, and user preferences

Keep it final-state oriented. Make clear what is current versus historical. Be concrete with paths and commands where that helps. Avoid routine chatter, raw logs, secrets, and unnecessary ceremony.

Treat repo state as context, not as an automatic instruction. Do not tell the next agent to commit, push, release, or otherwise perform project actions unless the user explicitly asked for that as the next step. If you include suggested next work, phrase it as possible continuation options, not commands.

Make clear that the handoff is orientation material. The next agent should review the handoff and inspect the current repo before making changes; it should not immediately edit code based only on the handoff.

After writing the file, briefly report the path and what the handoff captures.
