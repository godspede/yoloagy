#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Bash tab completion for yoloagy. Source it from ~/.bashrc:
#   source /path/to/yoloagy/completion/yoloagy.bash
#
# `yoloagy <Tab>` offers the aliases of live sessions named under the current
# directory's prefix, for reattaching; a new alias is just typed.
# `yoloagy -<Tab>` completes flags. Naming and listing come from yoloagy itself
# (`--prefix`, `--list`), so completion always agrees with what it launches.

_yoloagy_complete() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local flags="--restart --detach --here --no-worktree --worktree -l --list --prefix -h --help"
    local prefix s words=""

    if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$flags" -- "$cur")
        return
    fi

    prefix=$(command yoloagy --prefix 2>/dev/null) || return
    while IFS= read -r s; do
        [[ "$s" == "$prefix"-* ]] && words+=" ${s#"$prefix"-}"
    done < <(command yoloagy --list 2>/dev/null)
    mapfile -t COMPREPLY < <(compgen -W "$words" -- "$cur")
}
complete -F _yoloagy_complete yoloagy
