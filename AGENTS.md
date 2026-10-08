# Repository agent guidance

For adding a painting or refining wallpaper motion/masks, read
[author-painting-wallpaper](.agents/skills/author-painting-wallpaper/SKILL.md)
before implementation. Its references describe source rights, art direction,
native integration, and rendering evidence. Use only the parts relevant to the task.

The skill is ordinary Markdown with Python helpers. Agents that do not discover
`.agents/skills` automatically can read the entrypoint directly. Availability of
the skill does not imply that a platform can run AppKit or Metal.

Keep unrelated work and existing uncommitted changes intact. Do not represent a
cloud reference preview as native app verification.
