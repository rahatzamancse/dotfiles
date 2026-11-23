#!/bin/sh
# Skills come only from skillshare (claude + universal targets) and each agent's
# caveman plugin. Remove copies left by Skills Manager, npx skills, the old
# skillshare caveman, and Cursor built-in skills copied into ~/.agents/skills.
set -eu

rm -rf \
	"${HOME}/.skills-manager" \
	"${HOME}/.local/share/applications/skills-manager.desktop" \
	"${HOME}/.config/skillshare/skills/caveman" \
	"${HOME}/.agents/.skill-lock.json"

agents="${HOME}/.agents/skills"
for name in cavecrew caveman caveman-compress caveman-help caveman-stats find-skills; do
	rm -rf "${agents:?}/${name}"
done
for builtin in "${HOME}/.cursor/skills-cursor"/*/; do
	name=$(basename "$builtin")
	if [ -d "${agents}/${name}" ] && [ ! -L "${agents}/${name}" ]; then
		rm -rf "${agents:?}/${name}"
	fi
done

for dir in "${HOME}/.codex/skills" "${HOME}/.cursor/skills"; do
	[ -d "$dir" ] || continue
	find "$dir" -maxdepth 1 -type l -lname "${HOME}/.config/skillshare/skills/*" -delete
	rm -f "${dir}/.skillshare-manifest.json"
done

for dir in "${HOME}/.claude/skills" "${HOME}/.codex/skills" "${HOME}/.cursor/skills" "${HOME}/.config/opencode/skills"; do
	[ -d "$dir" ] || continue
	find "$dir" -maxdepth 1 -type l ! -exec test -e {} \; -delete
done
