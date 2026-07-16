#!/bin/sh
# Remove vendor paths that used to be tracked in the source tree and are now
# fetched via .chezmoiexternal (old layouts that would otherwise linger).
set -eu

rm -rf \
	"${HOME}/.config/mpv/scripts/Blackbox" \
	"${HOME}/.config/skillshare/skills/.metadata.json"
