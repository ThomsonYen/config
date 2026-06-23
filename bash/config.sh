#!/usr/bin/env bash
# config.sh — two-tiered config loader for bash.
#
# Reads config_default.yaml (committed defaults) and config.yaml (local
# overrides, gitignored). On first run, config.yaml is seeded from the
# defaults so you have a file to edit. At load time the two are merged:
# config.yaml wins, and any key it omits falls back to config_default.yaml.
#
# Usage:
#   source /path/to/bash/config.sh
#   config_load                      # uses repo root (../ from this file)
#   config_load /some/config/dir     # or point it at an explicit dir
#
#   config get app.name              # → my-app
#   config get app.workers           # → 4   (falls back to defaults)
#   config get features              # → list, one item per line
#   config keys                      # all dotted keys (union of both tiers)
#   config destroy                   # tear down all loaded state
#
# Pass "strict" as 2nd arg to config_load to error on unset ${env:VAR}.

# Resolve the directory this file lives in (works when sourced).
_config_sh_dir() {
    local src="${BASH_SOURCE[0]}"
    cd "$(dirname "$src")" >/dev/null 2>&1 && pwd
}

# shellcheck source=yaml_parser.sh
source "$(_config_sh_dir)/yaml_parser.sh"

# config_load [config_dir] [strict]
#   config_dir defaults to the repo root (one level up from this file).
config_load() {
    local config_dir="${1:-$(_config_sh_dir)/..}"
    local strict="${2:-}"

    local default_file="${config_dir}/config_default.yaml"
    local user_file="${config_dir}/config.yaml"

    if [[ ! -f "$default_file" ]]; then
        echo "config_load: defaults not found: $default_file" >&2
        return 1
    fi

    # Tier 2: create config.yaml from defaults on first run, dropping
    # whole-line comments (lines whose first non-blank char is #).
    if [[ ! -f "$user_file" ]]; then
        grep -v '^[[:space:]]*#' "$default_file" | sed '/./,$!d' > "$user_file" || return 1
        echo "config_load: created $user_file from defaults — edit as needed" >&2
    fi

    # Reset any previous load.
    declare -F _cfg_def >/dev/null 2>&1 && _cfg_def destroy
    declare -F _cfg_usr >/dev/null 2>&1 && _cfg_usr destroy

    yaml_parse_dict "$default_file" _cfg_def "$strict" || return 1
    yaml_parse_dict "$user_file"   _cfg_usr "$strict" || return 1

    # True if KEY is present in the user tier (config.yaml). A key that exists
    # but holds an empty value still counts as present. Defined here (not at
    # source scope) so it is recreated after a `config destroy`.
    _config_user_has() {
        _cfg_usr keys | grep -Fxq "$1"
    }

    # Build the merged accessor.
    config() {
        local cmd="$1"; shift
        case "$cmd" in
            get)
                local key="$1"
                # User value wins only if the key is actually present there.
                if _config_user_has "$key"; then
                    _cfg_usr get "$key"
                else
                    _cfg_def get "$key"
                fi
                ;;
            keys)
                { _cfg_def keys; _cfg_usr keys; } | sort -u
                ;;
            dump)
                local k
                while IFS= read -r k; do
                    printf '%s=%s\n' "$k" "$(config get "$k")"
                done < <(config keys)
                ;;
            destroy)
                declare -F _cfg_def >/dev/null 2>&1 && _cfg_def destroy
                declare -F _cfg_usr >/dev/null 2>&1 && _cfg_usr destroy
                unset -f config _config_user_has
                ;;
            *)
                echo "config: unknown command: $cmd" >&2
                return 1
                ;;
        esac
    }
}
