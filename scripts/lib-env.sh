#!/usr/bin/env bash
# Shared helper: locate and source the team env file.
# Order: $CN_ENV, ~/cn-team.env, <repo>/config/cn-team.env
cn_load_env() {
    local root="$1" f
    for f in "${CN_ENV:-}" "$HOME/cn-team.env" "$root/config/cn-team.env"; do
        if [ -n "$f" ] && [ -f "$f" ]; then
            # shellcheck disable=SC1090
            source "$f"
            return 0
        fi
    done
    echo "Error: no env file. Copy config/cn-team.env.example to ~/cn-team.env and fill in the IPs." >&2
    exit 1
}
