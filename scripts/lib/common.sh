#!/usr/bin/env sh

set -euf

is_help() {
    case "$1" in
    -h | --help | help)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

log() {
    if [ $# -le 1 ]; then
        printf '[helm-secrets] %s\n' "${1:-}"
    else
        format="${1}"
        shift

        # shellcheck disable=SC2059
        printf "[helm-secrets] $format\n" "$@"
    fi
}

error() {
    log "$@" >&2
}

fatal() {
    error "$@"

    exit 1
}

load_secret_driver() {
    driver="${1}"
    if [ -f "${SCRIPT_DIR}/drivers/${driver}.sh" ]; then
        # shellcheck source=scripts/drivers/sops.sh
        . "${SCRIPT_DIR}/drivers/${driver}.sh"
    else
        # Allow to load out of tree drivers.
        if [ ! -f "${driver}" ]; then
            fatal "Can't find secret driver: %s" "${driver}"
        fi

        # shellcheck disable=SC2034
        HELM_SECRETS_SCRIPT_DIR="${SCRIPT_DIR}"

        # shellcheck source=tests/assets/custom-driver.sh
        . "${driver}"
    fi
}

_regex_escape() {
    # This is a function because dealing with quotes is a pain.
    # http://stackoverflow.com/a/2705678/120999
    sed -e 's/[]\/()$*.^|[]/\\&/g'
}

_trap() {
    if command -v _trap_hook >/dev/null; then
        _trap_hook
    fi

    if command -v _trap_kill_gpg_agent >/dev/null; then
        _trap_kill_gpg_agent
    fi

    rm -rf "${TMPDIR}"
}

# MacOS syntax and behavior is different for mktemp
# https://unix.stackexchange.com/a/555214
_mktemp() {
    mktemp "$@" "${TMPDIR}/XXXXXX"
}

_convert_path() {
    if on_wsl; then
        touch "${1}"
        case "${1}" in
        /mnt/*)
            printf '%s' "$(wslpath -w "${1}")"
            ;;
        *)
            printf '%s' "${1}"
            ;;
        esac
    else
        printf '%s' "${1}"
    fi
}

# MacOS syntax is different for in-place
# https://unix.stackexchange.com/a/92907/433641
_sed_i() { sed -i "$@"; }

on_cygwin() { false; }

case "$(uname -s)" in
CYGWIN*)
    on_cygwin() { true; }
    ;;
Darwin)
    case $(sed --help 2>&1) in
    *BusyBox* | *GNU*) ;;
    *) _sed_i() { sed -i '' "$@"; } ;;
    esac
    ;;
esac

if [ -f /proc/version ] && grep -qi microsoft /proc/version; then
    on_wsl() { true; }
else
    on_wsl() { false; }
fi
