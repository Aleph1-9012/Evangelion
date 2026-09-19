#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Aleph1-9012
# Shared installation functions for eva; supports existing installation records.

set -Eeuo pipefail
export LC_ALL=C

EVA_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DEFAULTS=etc/default/grub
GRUB_DIR=boot/grub
GRUB_DIR_OPTION=
LAYOUT_AMBIGUOUS=0
CONFIG=$GRUB_DIR/grub.cfg
RUNTIME=$GRUB_DIR/themes/evangelion
HOOK=etc/grub.d/99_evangelion
STATE=var/lib/evangelion-grub/state.json
BACKUP=var/lib/evangelion-grub/grub.cfg.previous
LIBRARY=usr/local/share/evangelion
COMMAND=usr/local/bin/eva
MANAGER=var/lib/evangelion-grub/manager.json
PREVIOUS=var/lib/evangelion-grub/previous
BOOT_RUNTIME=var/lib/evangelion-grub/boot
BOOT_HELPER=$BOOT_RUNTIME/boot-console
BOOT_PARSER=$BOOT_RUNTIME/boot-console.awk
BOOT_PROXY=$BOOT_RUNTIME/grub.d/00_console
BEGIN='# BEGIN EVANGELION GRUB (managed; use install.sh --uninstall)'
# Recognize blocks written before install and uninstall shared one entry point.
LEGACY_BEGIN='# BEGIN EVANGELION GRUB (managed; use uninstall.sh)'
END='# END EVANGELION GRUB'
THEMES=()
declare -A THEME_NAMES=()
PROFILES=(720p 1080p 1440p)
WORK='' CANDIDATE='' ATOMIC_TEMP='' TRANSACTION=0
ROOT=/ SOURCE="$EVA_REPO/themes" MODE='' GENERATOR='' ACTION='' DRY_RUN=0 QUIET=0 DEPLOY=0
STATE_DATA=null MANAGER_DATA=null
NEXT_FILE=0
# Plan values are private temporary files; an empty value means removal.
declare -A PLAN=() FILES=() SAVED=() CREATED_SET=()
declare -a SAVED_ORDER=() CREATED_DIRS=()

die() { printf 'eva: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "$1 is required."; }
sha() { local result; result=$(sha256sum -- "$1") || die "Cannot hash $1"; printf '%s' "${result%% *}"; }
shell_quote() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
record() { awk -f "$EVA_REPO/bin/state-data.awk" -- "$@"; }

safe_path() {
    local relative=$2 part cursor=$1
    [[ $relative =~ ^[A-Za-z0-9_./-]+$ && $relative != /* ]] || die "Unsafe relative path: $relative"
    local -a parts
    IFS=/ read -r -a parts <<< "$relative"
    for part in "${parts[@]}"; do
        [[ -n $part && $part != . && $part != .. ]] || die "Unsafe relative path: $relative"
        cursor=${cursor%/}/$part
        [[ ! -L $cursor ]] || die "Refusing symlink: $cursor"
    done
    printf '%s' "$cursor"
}

regular_or_absent() {
    [[ ! -e $1 || -f $1 ]] || die "Expected a regular file: $1"
}

profile_mode() {
    case $1 in 720p) printf '1280x720';; 1080p) printf '1920x1080';; 1440p) printf '2560x1440';; *) die "Unknown profile: $1";; esac
}

load_catalog() {
    local catalog theme name entries
    THEMES=(); THEME_NAMES=()
    catalog=$(safe_path "$SOURCE" catalog.json)
    # Uninstall and rollback can use saved ownership without the source catalog.
    [[ -f $catalog ]] || return 0
    entries=$(record catalog < "$catalog") || die 'Invalid theme catalog'
    [[ -n $entries ]] || return 0
    while IFS=$'\t' read -r theme name; do
        THEMES+=("$theme"); THEME_NAMES["$theme"]=$name
    done <<< "$entries"
}

mode_for() {
    local profile=$1 mode=$2 defaults=${3:-} native w h nw nh line value
    native=$(profile_mode "$profile")
    if [[ -z $mode && $profile == 1440p && -n $defaults ]]; then
        # Read literal assignments only. Never source the user's defaults.
        while IFS= read -r line || [[ -n $line ]]; do
            if [[ $line =~ ^[[:space:]]*GRUB_GFXMODE[[:space:]]*=[[:space:]]*([\"\']?)([0-9]+x[0-9]+)([\"\']?)[[:space:]]*$ ]]; then
                value=${BASH_REMATCH[2]}
                w=${value%x*}; h=${value#*x}
                if [[ $w =~ ^[1-9][0-9]{2,4}$ && $h =~ ^[1-9][0-9]{2,4}$ ]] && ((w >= 2560 && h >= 1440)); then mode=$value; else mode=; fi
            fi
        done < "$defaults"
    fi
    mode=${mode:-$native}
    [[ $mode =~ ^[1-9][0-9]{2,4}x[1-9][0-9]{2,4}$ ]] || die '--gfxmode must be one exact WIDTHxHEIGHT mode, without auto or fallback lists'
    w=${mode%x*}; h=${mode#*x}; nw=${native%x*}; nh=${native#*x}
    ((w >= nw && h >= nh)) || die "$mode is smaller than the $profile design ($native)"
    printf '%s' "$mode"
}

validate_hashes() {
    local data=$1 prefix=$2 path
    record hashes <<< "$data" || die 'Unsafe ownership manifest'
    while IFS=$'\t' read -r path _; do
        [[ -n $path ]] || continue
        safe_path "$ROOT" "$path" >/dev/null
        [[ $path == "$prefix/"* || ( $prefix == "$LIBRARY" && $path == "$COMMAND" ) ]] || die "Unsafe ownership path: $path"
    done < <(record pairs <<< "$data")
}

validate_choice() {
    local data=$1 theme profile mode
    record choice "$RUNTIME" <<< "$data" || die 'Invalid theme-choice record'
    theme=$(record get theme <<< "$data"); profile=$(record get profile <<< "$data"); mode=$(record get gfxmode <<< "$data")
    [[ $theme =~ ^[a-z][a-z0-9_-]*$ ]] || die 'Invalid theme-choice record'
    mode_for "$profile" "$mode" >/dev/null
    validate_hashes "$(record get files <<< "$data")" "$RUNTIME"
}

load_state() {
    local path
    detect_grub_layout
    STATE_DATA=null
    path=$(safe_path "$ROOT" "$STATE"); regular_or_absent "$path"
    if [[ -f $path ]]; then
        STATE_DATA=$(cat -- "$path")
        record state "$BEGIN" "$LEGACY_BEGIN" <<< "$STATE_DATA" || die 'Unsupported or damaged ownership manifest'
        validate_choice "$STATE_DATA"
        validate_hashes "$(record get boot_files '{}' <<< "$STATE_DATA")" "$BOOT_RUNTIME"
        if [[ $(record get previous null <<< "$STATE_DATA") != null ]]; then validate_choice "$(record get previous <<< "$STATE_DATA")"; fi
    fi
}

load_manager() {
    local path
    MANAGER_DATA=null
    path=$(safe_path "$ROOT" "$MANAGER"); regular_or_absent "$path"
    if [[ -f $path ]]; then
        MANAGER_DATA=$(cat -- "$path")
        record manager <<< "$MANAGER_DATA" || die 'Unsupported or damaged manager manifest'
        validate_hashes "$(record get files <<< "$MANAGER_DATA")" "$LIBRARY"
    fi
}

font_name() {
    local file=$1 header offset=12 length tag size b0 b1 b2 b3
    # Generated PF2 files put NAME first. Read that short header in one pass;
    # retain the section reader for longer names and other valid layouts.
    if header=$(od -An -v -tu1 -N256 -- "$file" | awk '
        { for (i=1; i<=NF; i++) b[++n]=$i }
        END {
            split("70 73 76 69 0 0 0 4 80 70 70 50 78 65 77 69", signature)
            if (n<20) exit 1
            for (i=1; i<=16; i++) if (b[i]!=signature[i]) exit 1
            size=((b[17]*256+b[18])*256+b[19])*256+b[20]
            if (size>n-20) exit 1
            for (i=21; i<=20+size; i++) if (b[i]) printf "%c",b[i]
        }'); then
        printf '%s' "$header"
        return
    fi
    header=$(od -An -tx1 -N12 -- "$file" | tr -d ' \n')
    [[ $header == 46494c450000000450464632 ]] || die 'Runtime font has an invalid PF2 header'
    length=$(stat -c %s -- "$file")
    while ((offset + 8 <= length)); do
        tag=$(dd if="$file" bs=1 skip="$offset" count=4 status=none)
        read -r b0 b1 b2 b3 < <(od -An -tu1 -j "$((offset + 4))" -N4 -- "$file")
        size=$((b0 * 16777216 + b1 * 65536 + b2 * 256 + b3))
        offset=$((offset + 8))
        [[ $tag != DATA ]] || break
        ((size <= length - offset)) || die 'Runtime font has a truncated PF2 section'
        if [[ $tag == NAME ]]; then
            dd if="$file" bs=1 skip="$offset" count="$size" status=none | tr -d '\000'
            return
        fi
        offset=$((offset + size))
    done
    die 'Runtime font has no PF2 NAME section'
}

validate_references() {
    local -n resources=$1
    local path relative name header line key value suffix rest count i card_host=0 modules=0
    local -A names=() images=()
    local property='^[[:space:]]*([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*[:=][[:space:]]*(.*)$'
    local quoted='^"([^"]*)"' unquoted='^([^[:space:]#}]+)'
    [[ -v resources[$RUNTIME/theme.txt] ]] || die 'Ready theme is missing theme.txt'
    for path in "${!resources[@]}"; do
        case $path in
            *.pf2) name=$(font_name "${resources[$path]}") || die 'Invalid runtime font'; names["$name"]=1;;
            *.png)
                IFS= read -r -d '' -n 8 header < "${resources[$path]}" || die "Truncated PNG: $path"
                [[ $header == $'\x89PNG\r\n\x1a\n' ]] || die "Runtime PNG has an invalid signature: $path"
                images["${path#"$RUNTIME/"}"]=1;;
            *.mod)
                modules=$((modules + 1))
                IFS= read -r -d '' -n 4 header < "${resources[$path]}" || die "Truncated module: $path"
                [[ $header == $'\x7fELF' ]] || die "Invalid native GRUB module: $path";;
        esac
    done
    ((${#images[@]} && ${#names[@]})) || die 'Ready theme needs PNG artwork and PF2 fonts'
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ $property ]] || continue
        key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
        if [[ $value =~ $quoted ]]; then value=${BASH_REMATCH[1]}; elif [[ $value =~ $unquoted ]]; then value=${BASH_REMATCH[1]}; else continue; fi
        case $key in
            id) [[ $value != evangelion-cards ]] || card_host=1;;
            desktop-image|file|center_bitmap|tick_bitmap)
                [[ -n $value && -v images[$value] ]] || die "Missing or unsupported theme image reference: $key=$value";;
            item_pixmap_style|selected_item_pixmap_style|menu_pixmap_style|scrollbar_frame|scrollbar_thumb|bar_style|highlight_style)
                [[ $value =~ ^[A-Za-z0-9_./-]+_\*\.png$ ]] || die "Unsupported styled-box reference: $value"
                count=0
                for relative in "${!images[@]}"; do
                    # The generated styled-box reference is a validated glob.
                    # shellcheck disable=SC2053
                    if [[ $relative == $value ]]; then
                        suffix=${relative#"${value%\**}"}; suffix=${suffix%.png}
                        case $suffix in c|n|s|e|w|nw|ne|sw|se) ;; *) die "Invalid styled-box slice: $relative";; esac
                        count=$((count + 1))
                    fi
                done
                ((count)) || die "Missing styled-box slices: $value";;
            font|item_font|selected_item_font|title-font|message-font|terminal-font)
                [[ -n $value && -v names[$value] ]] || die "Theme font is not present in the packaged PF2 files: $value";;
        esac
    done < "${resources[$RUNTIME/theme.txt]}"
    if ((card_host || modules)); then
        [[ -v resources[$RUNTIME/cards.cfg] ]] || die 'Missing native card configuration'
    fi
    if [[ -v resources[$RUNTIME/cards.cfg] ]]; then
        ((card_host)) || die 'Missing native card canvas'
        count=0
        while IFS= read -r line || [[ -n $line ]]; do
            [[ -z $line || $line == \#* ]] && continue
            count=$((count + 1))
            [[ $line == 'evangelion_cards '* ]] || die 'Invalid card configuration command'
            rest=${line#evangelion_cards }
            for ((i=0; i<16; i++)); do
                [[ $rest =~ ^([0-9]+)[[:space:]]+(.*)$ ]] || die 'Invalid card geometry'
                value=${BASH_REMATCH[1]}; rest=${BASH_REMATCH[2]}
                [[ ${#value} -le 5 ]] && ((10#$value <= 16384)) || die 'Card geometry is out of range'
            done
            for ((i=0; i<6; i++)); do
                [[ $rest =~ $quoted ]] || die 'Invalid card font or color'
                value=${BASH_REMATCH[1]}; rest=${rest#\"$value\"}; rest=${rest# }
                if ((i<3)); then
                    [[ -v names[$value] ]] || die "Card font is not packaged: $value"
                else
                    [[ $value =~ ^#[[:xdigit:]]{6}$ ]] || die 'Invalid card color'
                fi
            done
            [[ -z $rest ]] || die 'Unexpected card configuration arguments'
        done < "${resources[$RUNTIME/cards.cfg]}"
        ((count == 1)) || die 'Expected one card configuration command'
        [[ -v resources[$RUNTIME/modules/x86_64-efi/evangelion_cards.mod] ]] || die 'Missing native card module'
    fi
}

# Keep the existing JSON installation format, parsed as data by state-data.awk.
hash_map() {
    local -n entries=$1
    local path item i
    local -a keys=() inputs=()
    for path in "${!entries[@]}"; do
        keys+=("$path"); inputs+=("${entries[$path]}")
    done
    # Bound each invocation and keep file names unambiguous, even outside the source tree.
    {
        for ((i=0; i<${#inputs[@]}; i+=256)); do
            sha256sum --zero -- "${inputs[@]:i:256}" || return 1
        done
    } | {
        i=0
        while IFS= read -r -d '' item; do
            printf '%s\t%s\n' "${keys[$i]}" "${item:0:64}"
            i=$((i + 1))
        done
        ((${#keys[@]} == i))
    } | record hash-map
}

source_files() {
    local theme=$1 profile=$2 base ready native path relative hashes expected
    local -A assets=()
    FILES=()
    base=$(safe_path "$SOURCE" "$theme/$profile")
    ready=$(safe_path "$base" runtime-ready.json)
    [[ -f $ready ]] || die "Theme is unavailable: $theme/$profile has no readiness record"
    native=$(profile_mode "$profile")
    expected=$(record readiness "$theme" "$profile" "$native" < "$ready") || die "Invalid readiness record: $theme/$profile"
    while IFS=$'\t' read -r relative _; do safe_path "$base" "$relative" >/dev/null; done < <(record pairs <<< "$expected")
    while IFS= read -r -d '' path; do
        relative=${path#"$base/"}
        safe_path "$base" "$relative" >/dev/null
        [[ -f $path || -d $path ]] || die "Source contains a non-regular file: $path"
        [[ -f $path && $relative != runtime-ready.json ]] || continue
        # hash_map reads this array through a nameref.
        # shellcheck disable=SC2034
        assets["$relative"]=$path
        case $relative in theme.txt|cards.cfg|*.png|fonts/*.pf2|modules/*/evangelion_cards.mod) FILES["$RUNTIME/$relative"]=$path;; esac
    done < <(find "$base" -mindepth 1 -print0)
    hashes=$(hash_map assets) || die 'Cannot hash theme assets'
    [[ $hashes == "$expected" ]] || die "Runtime files differ from the readiness record; rebuild: $theme/$profile"
    validate_references FILES
}

plan_add() {
    local relative=$1 source=${2:-} path
    path=$(safe_path "$ROOT" "$relative"); regular_or_absent "$path"
    if [[ -z $source && ! -e $path ]] || { [[ -n $source && -f $path ]] && cmp -s -- "$path" "$source"; }; then
        unset 'PLAN[$relative]'
        return
    fi
    if [[ -z $source ]]; then
        PLAN["$relative"]=
    else
        NEXT_FILE=$((NEXT_FILE + 1))
        cp -- "$source" "$WORK/new/$NEXT_FILE"
        PLAN["$relative"]=$WORK/new/$NEXT_FILE
    fi
}

owned_changes() {
    local old=$1 removing=$3 relative current expected hashes
    local -n desired=$2
    local -A union=() old_hashes=() current_files=() current_hashes=()
    while IFS=$'\t' read -r relative expected; do union["$relative"]=1; old_hashes["$relative"]=$expected; done < <(record pairs <<< "$old")
    for relative in "${!desired[@]}"; do union["$relative"]=1; done
    for relative in "${!old_hashes[@]}"; do
        current=$(safe_path "$ROOT" "$relative"); regular_or_absent "$current"
        if [[ -f $current ]]; then current_files["$relative"]=$current; fi
    done
    hashes=$(hash_map current_files) || die 'Cannot hash owned files'
    while IFS=$'\t' read -r relative expected; do
        [[ -z $relative ]] || current_hashes["$relative"]=$expected
    done < <(record pairs <<< "$hashes")
    for relative in "${!union[@]}"; do
        current=$(safe_path "$ROOT" "$relative"); regular_or_absent "$current"
        expected=${old_hashes[$relative]:-}
        if [[ -n $expected ]]; then
            if [[ -f $current && ${current_hashes[$relative]:-} != "$expected" ]]; then
                if ((removing)); then printf 'Preserving modified file: /%s\n' "$relative"; continue; fi
                die "Refusing to overwrite a modified owned file: /$relative"
            fi
        elif [[ -e $current ]]; then die "Refusing to overwrite an unowned file: /$relative"
        fi
        plan_add "$relative" "${desired[$relative]:-}"
    done
}

plan_manager() {
    local removing=${1:-0} relative path theme profile base count=0
    local -A manager_files=()
    load_manager
    if ((!removing)); then
        for relative in bin/install.sh bin/eva bin/boot-console bin/boot-console.awk bin/state-data.awk bin/grub-generator LICENSE docs/NOTICE.md docs/ADVANCED.md docs/BOOT_CONSOLE.md; do
            path=$(safe_path "$EVA_REPO" "$relative")
            [[ -f $path ]] || die "Missing package file: $relative"
            manager_files["$LIBRARY/$relative"]=$path
        done
        while IFS= read -r -d '' path; do
            relative=${path#"$EVA_REPO/"}
            safe_path "$EVA_REPO" "$relative" >/dev/null
            manager_files["$LIBRARY/$relative"]=$path
        done < <(find "$EVA_REPO/docs/licenses" -type f -print0)
        manager_files["$COMMAND"]=${manager_files[$LIBRARY/bin/eva]}
        [[ -f $SOURCE/catalog.json ]] || die 'Missing theme catalog'
        manager_files["$LIBRARY/themes/catalog.json"]=$SOURCE/catalog.json
        for theme in "${THEMES[@]}"; do for profile in "${PROFILES[@]}"; do
            base=$(safe_path "$SOURCE" "$theme/$profile")
            path=$(safe_path "$base" runtime-ready.json)
            [[ -f $path ]] || continue
            source_files "$theme" "$profile"
            while IFS= read -r -d '' path; do
                relative=${path#"$base/"}
                manager_files["$LIBRARY/themes/$theme/$profile/$relative"]=$path
            done < <(find "$base" -type f -print0)
            count=$((count + 1))
        done; done
        ((count)) || die 'No ready theme profiles are available for the manager'
    fi
    owned_changes "$(record get files '{}' <<< "$MANAGER_DATA")" manager_files "$removing"
    if ((removing)); then plan_add "$MANAGER"; else
        # The full catalog can exceed the OS limit for one argv string.
        hash_map manager_files | record wrap-manager > "$WORK/manager.json"
        plan_add "$MANAGER" "$WORK/manager.json"
    fi
}

detect_grub_layout() {
    local state_path recorded='' candidate path
    local -a available=()
    LAYOUT_AMBIGUOUS=0
    state_path=$(safe_path "$ROOT" "$STATE")
    regular_or_absent "$state_path"
    if [[ -f $state_path ]]; then
        # Existing ownership paths record the directory, including v1 manifests.
        recorded=$(record grub-dir < "$state_path") || die 'Cannot determine the configured GRUB directory from state'
    fi
    if [[ -n $GRUB_DIR_OPTION ]]; then
        case $GRUB_DIR_OPTION in /boot/grub|/boot/grub2) ;; *) die '--grub-dir must be /boot/grub or /boot/grub2';; esac
        GRUB_DIR=${GRUB_DIR_OPTION#/}
        [[ -z $recorded || $recorded == "$GRUB_DIR" ]] || die 'The selected GRUB directory differs from the installed theme. Uninstall that theme before changing directories.'
    elif [[ -n $recorded ]]; then GRUB_DIR=$recorded
    else
        for candidate in boot/grub boot/grub2; do
            path=$(safe_path "$ROOT" "$candidate/grub.cfg")
            if [[ -f $path ]]; then available+=("$candidate"); fi
        done
        case ${#available[@]} in
            0) GRUB_DIR=boot/grub;; # Catalog-only installation does not need GRUB.
            1) GRUB_DIR=${available[0]};;
            *) GRUB_DIR=boot/grub; LAYOUT_AMBIGUOUS=1;;
        esac
    fi
    CONFIG=$GRUB_DIR/grub.cfg
    RUNTIME=$GRUB_DIR/themes/evangelion
}

find_grub_command() {
    local suffix=$1 command
    for command in "grub-$suffix" "grub2-$suffix"; do
        if command -v "$command" >/dev/null; then command -v "$command"; return; fi
    done
    die "grub-$suffix or grub2-$suffix is required. Install your distribution's GRUB tools."
}

strip_block() {
    record strip-block "$ROOT/$DEFAULTS" "$BEGIN" "$LEGACY_BEGIN" "$END" <<< "$STATE_DATA" > "$WORK/base-defaults"
}

make_hook() {
    local mode=$1 path
    cat <<HEADER
#!/bin/sh
exec tail -n +3 "\$0"
# Evangelion exact-mode loader
terminal_output console
unset theme
unset eva_defer_boot_terminal
set gfxmode=$mode,evangelion_no_auto_fallback
load_video
insmod gfxterm
insmod gfxmenu
insmod png
loadfont "\$prefix/fonts/unicode.pf2"
HEADER
    while IFS= read -r path; do
        [[ $path == *.pf2 ]] || continue
        # GRUB expands $prefix when the loader runs.
        # shellcheck disable=SC2016
        printf 'loadfont "$prefix/%s"\n' "${path#"$GRUB_DIR/"}"
    done < <(printf '%s\n' "${!FILES[@]}" | sort)
    if [[ -v FILES[$RUNTIME/cards.cfg] ]]; then
        # GRUB's insmod and source can return success after an error. Only the
        # native viewer sets this marker after accepting its configuration.
        cat <<'CARDS'
unset evangelion_cards_ready
if [ -f "$prefix/themes/evangelion/modules/$grub_cpu-$grub_platform/evangelion_cards.mod" ]; then
  insmod "$prefix/themes/evangelion/modules/$grub_cpu-$grub_platform/evangelion_cards.mod"
  set theme="$prefix/themes/evangelion/theme.txt"
  source "$prefix/themes/evangelion/cards.cfg"
  if [ "$evangelion_cards_ready" = 1 ]; then
    if terminal_output gfxterm; then
      export theme
    else
      unset theme
      terminal_output console
    fi
  else
    unset theme
    terminal_output console
  fi
fi
CARDS
        return
    fi
    cat <<'FOOTER'
if terminal_output gfxterm; then
  set theme="$prefix/themes/evangelion/theme.txt"
  export theme
else
  unset theme
  terminal_output console
fi
FOOTER
}

plan_changes() {
    local path relative expected old_files old_previous old_snapshot hashes previous newline mode boot_hashes
    # owned_changes reads these arrays through namerefs.
    # shellcheck disable=SC2034
    local -A snapshot=() empty=() boot_files=()
    if [[ $ACTION == setup ]]; then plan_manager; return; fi
    load_state
    if [[ $ACTION == uninstall ]]; then
        plan_manager 1
        [[ $STATE_DATA != null ]] || return 0
    fi
    ((LAYOUT_AMBIGUOUS == 0)) || die 'Both /boot/grub and /boot/grub2 contain configurations. Choose the active directory with --grub-dir.'
    for relative in "$DEFAULTS" "$CONFIG" etc/grub.d/00_header; do
        path=$(safe_path "$ROOT" "$relative")
        [[ -f $path ]] || die "Existing GRUB installation required: /$relative"
    done
    strip_block
    old_files=$(record get files '{}' <<< "$STATE_DATA")
    old_previous=$(record get previous 'null' <<< "$STATE_DATA")
    old_snapshot=$(record snapshot "$RUNTIME/" "$PREVIOUS/" <<< "$old_previous")
    path=$(safe_path "$ROOT" "$HOOK"); regular_or_absent "$path"
    if [[ $STATE_DATA != null ]]; then
        [[ -f $path && $(sha "$path") == "$(record get hook_hash <<< "$STATE_DATA")" ]] || die 'The managed loader changed; restore it before continuing'
    else [[ ! -e $path ]] || die "Refusing to overwrite an unowned /$HOOK"; fi
    if [[ $ACTION == uninstall ]]; then
        plan_add "$DEFAULTS" "$WORK/base-defaults"
        plan_add "$HOOK"; plan_add "$STATE"
        owned_changes "$old_files" empty 1
        owned_changes "$old_snapshot" empty 1
        owned_changes "$(record get boot_files '{}' <<< "$STATE_DATA")" empty 1
        return
    fi
    boot_files["$BOOT_HELPER"]=$EVA_REPO/bin/boot-console
    boot_files["$BOOT_PARSER"]=$EVA_REPO/bin/boot-console.awk
    boot_files["$BOOT_PROXY"]=$EVA_REPO/bin/grub-generator
    owned_changes "$(record get boot_files '{}' <<< "$STATE_DATA")" boot_files 0
    boot_hashes=$(hash_map boot_files)
    if [[ $ACTION == rollback ]]; then
        [[ $old_previous != null ]] || die 'No previous Evangelion choice is saved; use uninstall to restore the pre-Evangelion appearance'
        THEME=$(record get theme <<< "$old_previous"); PROFILE=$(record get profile <<< "$old_previous"); mode=$(record get gfxmode <<< "$old_previous")
        FILES=()
        while IFS=$'\t' read -r relative expected; do
            path=$(safe_path "$ROOT" "$PREVIOUS/${relative#"$RUNTIME/"}")
            [[ -f $path ]] || die "Previous theme snapshot is missing or modified: $path"
            FILES["$relative"]=$path
        done < <(record pairs files <<< "$old_previous")
        hashes=$(hash_map FILES) || die 'Cannot hash previous theme snapshot'
        [[ $hashes == "$(record get files <<< "$old_previous")" ]] || die 'Previous theme snapshot is missing or modified'
        validate_references FILES
    else
        source_files "$THEME" "$PROFILE"
        mode=$(mode_for "$PROFILE" "$MODE" "$WORK/base-defaults")
    fi
    owned_changes "$old_files" FILES 0
    hashes=$(hash_map FILES)
    printf '%s\n' "$hashes" > "$WORK/files.json"
    previous=$old_previous
    if [[ $STATE_DATA != null ]] && ! record same-choice "$THEME" "$PROFILE" "$mode" "$WORK/files.json" <<< "$STATE_DATA"; then
        while IFS=$'\t' read -r relative expected; do
            path=$(safe_path "$ROOT" "$relative")
            [[ -f $path ]] || die "Current theme cannot be saved for rollback: /$relative is missing or modified"
            # shellcheck disable=SC2034
            snapshot["$PREVIOUS/${relative#"$RUNTIME/"}"]=$path
        done < <(record pairs <<< "$old_files")
        hashes=$(hash_map snapshot) || die 'Cannot hash current theme snapshot'
        [[ $hashes == "$(record snapshot "$RUNTIME/" "$PREVIOUS/" <<< "$STATE_DATA")" ]] || die 'Current theme cannot be saved for rollback: files were modified'
        owned_changes "$old_snapshot" snapshot 0
        previous=$(record choice-record <<< "$STATE_DATA")
    fi
    {
        printf '%s\n' "$BEGIN" '# The late loader selects the theme only after the exact mode succeeds.' 'GRUB_THEME=""' 'GRUB_FONT=""' "GRUB_GFXMODE=\"$mode\"" 'GRUB_TIMEOUT_STYLE="menu"'
        printf '%s\n' '# Process the current GRUB generators on every configuration refresh.' 'if [ -n "${grub_mkconfig_dir-}" ]; then' '  export EVANGELION_GRUB_SOURCE_DIR="$grub_mkconfig_dir"'
        if [[ $THEME == ayanami || $THEME == seele ]]; then
            printf '%s\n' '  export EVANGELION_NUMBERED_MENU=1'
        fi
        printf '  grub_mkconfig_dir=%s\n' "$(shell_quote "${ROOT%/}/$BOOT_RUNTIME/grub.d")"
        printf '%s\n' 'fi' "$END"
    } > "$WORK/block"
    newline=$(record newline "$WORK/base-defaults")
    cat -- "$WORK/base-defaults" > "$WORK/defaults"
    if [[ $newline == true ]]; then printf '\n' >> "$WORK/defaults"; fi
    cat -- "$WORK/block" >> "$WORK/defaults"
    make_hook "$mode" > "$WORK/hook"
    printf '%s\n' "$STATE_DATA" > "$WORK/old-state.json"
    printf '%s\n' "$previous" > "$WORK/previous.json"
    printf '%s\n' "$boot_hashes" > "$WORK/boot-files.json"
    record write-state "$WORK" "$THEME" "$PROFILE" "$mode" "$(sha "$WORK/hook")" "$newline" > "$WORK/state.json"
    plan_add "$DEFAULTS" "$WORK/defaults"; plan_add "$HOOK" "$WORK/hook"; plan_add "$STATE" "$WORK/state.json"
    if ((DEPLOY)); then plan_manager; fi
    printf 'Selected %s %s, exact graphics mode %s.\n' "$THEME" "$PROFILE" "$mode"
}

prune_plan() {
    local relative path source
    for relative in "${!PLAN[@]}"; do
        path=$(safe_path "$ROOT" "$relative"); source=${PLAN[$relative]}
        if [[ -z $source && ! -e $path ]] || { [[ -n $source && -f $path ]] && cmp -s -- "$path" "$source"; }; then unset 'PLAN[$relative]'; fi
    done
}

needs_generation() { [[ -v PLAN[$DEFAULTS] || -v PLAN[$HOOK] || -v PLAN[$STATE] ]]; }

display_plan() {
    local relative path source operation status
    printf 'Target root: %s\n' "$ROOT"
    while IFS= read -r relative; do
        [[ -n $relative ]] || continue
        path=$(safe_path "$ROOT" "$relative"); source=${PLAN[$relative]}
        if [[ $relative == "$DEFAULTS" || $relative == "$HOOK" ]]; then
            [[ -e $path ]] || path=/dev/null
            diff -u --label "/$relative (current)" --label "/$relative (proposed)" "$path" "${source:-/dev/null}" || { status=$?; ((status == 1)) || die 'Cannot display diff'; }
        elif [[ -z $source ]]; then printf 'remove: /%s\n' "$relative"; else
            operation=create; [[ ! -e $path ]] || operation=replace
            printf '%s: /%s (%s bytes, sha256 %s)\n' "$operation" "$relative" "$(stat -c %s -- "$source")" "$(sha "$source")"
        fi
    done < <(printf '%s\n' "${!PLAN[@]}" | sort)
    if needs_generation; then printf 'Regenerate and syntax-check /%s; retain one prior configuration at /%s.\n' "$CONFIG" "$BACKUP"; fi
}

remember() {
    local relative=$1 path index parent i
    [[ ! -v SAVED[$relative] ]] || return 0
    path=$(safe_path "$ROOT" "$relative"); regular_or_absent "$path"
    index=${#SAVED_ORDER[@]}
    if [[ -f $path ]]; then cp -p -- "$path" "$WORK/old/$index"; fi
    SAVED_ORDER+=("$relative"); SAVED["$relative"]=$index
    local -a missing=()
    parent=${path%/*}
    while [[ ! -d $parent ]]; do missing+=("$parent"); parent=${parent%/*}; done
    for ((i=${#missing[@]}-1; i>=0; i--)); do
        parent=${missing[$i]}
        if [[ ! -v CREATED_SET[$parent] ]]; then
            mkdir -m 755 -- "$parent"
            CREATED_SET["$parent"]=1; CREATED_DIRS+=("$parent")
        fi
    done
}

atomic_write() {
    local relative=$1 source=$2 override=${3:-} path old mode=644
    path=$(safe_path "$ROOT" "$relative") || return 1
    [[ ! -e $path || -f $path ]] || return 1
    old=$WORK/old/${SAVED[$relative]}
    if [[ -f $old ]]; then mode=$(stat -c %a -- "$old") || return 1; fi
    mode=${override:-$mode}
    ATOMIC_TEMP=$(mktemp "${path%/*}/.${path##*/}.evangelion-XXXXXX") || return 1
    cat -- "$source" > "$ATOMIC_TEMP" || return 1
    if ((EUID == 0)) && [[ -f $old ]]; then chown --reference="$old" -- "$ATOMIC_TEMP" || return 1; fi
    chmod "$mode" -- "$ATOMIC_TEMP" || return 1
    sync -f -- "$ATOMIC_TEMP" || return 1
    mv -fT -- "$ATOMIC_TEMP" "$path" || return 1
    ATOMIC_TEMP=
}

transaction_change() {
    local relative=$1 source=${2:-} mode=${3:-}
    remember "$relative"
    if [[ -z $source ]]; then rm -f -- "$ROOT/$relative"; else atomic_write "$relative" "$source" "$mode"; fi
}

cleanup() {
    local status=$? i relative old path failed=0
    trap - EXIT INT TERM HUP
    set +e
    [[ -z $ATOMIC_TEMP ]] || rm -f -- "$ATOMIC_TEMP"
    ATOMIC_TEMP=
    if ((TRANSACTION)); then
        for ((i=${#SAVED_ORDER[@]}-1; i>=0; i--)); do
            relative=${SAVED_ORDER[$i]}; old=$WORK/old/$i
            path=$(safe_path "$ROOT" "$relative") || { failed=1; continue; }
            if [[ -f $old ]]; then
                # Restore content and original mode/ownership with atomic replacement.
                atomic_write "$relative" "$old" || failed=1
            else rm -f -- "$path" || failed=1; fi
        done
        for ((i=${#CREATED_DIRS[@]}-1; i>=0; i--)); do rmdir -- "${CREATED_DIRS[$i]}" 2>/dev/null || :; done
        if ((failed)); then printf 'eva: Recovery was incomplete. Saved files remain at %s/old.\n' "$WORK" >&2
        else printf 'Operation failed; changed files were restored and the previous grub.cfg retained.\n' >&2; fi
        ((status != 0)) || status=1
    fi
    [[ -z $ATOMIC_TEMP ]] || rm -f -- "$ATOMIC_TEMP"
    [[ -z $CANDIDATE ]] || rm -f -- "$CANDIDATE" "$CANDIDATE.new"
    if [[ -n $WORK ]] && ((failed == 0)); then rm -rf -- "$WORK"; fi
    if ((status > 0 && status < 128)); then status=1; fi
    exit "$status"
}

remove_empty_owned_dirs() {
    local relative prefix parent
    local -A directories=()
    for relative in "${!PLAN[@]}"; do
        [[ -z ${PLAN[$relative]} ]] || continue
        for prefix in "$RUNTIME" "$PREVIOUS" "$LIBRARY" "$BOOT_RUNTIME"; do
            [[ $relative == "$prefix/"* ]] || continue
            parent=${relative%/*}
            while [[ $parent == "$prefix" || $parent == "$prefix/"* ]]; do directories["$parent"]=1; parent=${parent%/*}; done
        done
    done
    while IFS= read -r relative; do
        [[ -n $relative ]] || continue
        parent=$(safe_path "$ROOT" "$relative")
        rmdir -- "$parent" 2>/dev/null || :
    done < <(printf '%s\n' "${!directories[@]}" | sort -r)
}

apply_changes() {
    local relative mode regenerate=0 checker
    local -a generator=()
    ((${#PLAN[@]})) || { printf 'Already in the requested state; no changes.\n'; return; }
    [[ $ROOT != / || $EUID == 0 ]] || die 'Host installation requires root; inspect --dry-run before running with sudo'
    if needs_generation; then
        regenerate=1
        checker=$(find_grub_command script-check)
        if [[ $ROOT != / ]]; then
            [[ -n $GENERATOR ]] || die 'A staging root requires --generator EXECUTABLE; host grub-mkconfig is never run against a stage'
            generator=("$(realpath -e -- "$GENERATOR")" "$ROOT")
        else
            [[ -z $GENERATOR ]] || die '--generator is available only with a staging --root'
            generator=("$(find_grub_command mkconfig)" -o)
            grep -q '^grub_mkconfig_dir=' "${generator[0]}" &&
                grep -q 'for .*grub_mkconfig_dir' "${generator[0]}" ||
                die 'This grub-mkconfig does not expose the supported generator directory'
        fi
        # Test the boot destination before changing defaults or runtime files.
        CANDIDATE=$(mktemp "${ROOT%/}/$GRUB_DIR/.grub.cfg.evangelion-XXXXXX")
    fi
    TRANSACTION=1
    for relative in "${!PLAN[@]}"; do
        [[ $relative != "$STATE" && $relative != "$MANAGER" ]] || continue
        mode=
        case $relative in "$HOOK"|"$COMMAND"|"$LIBRARY/bin/eva"|"$LIBRARY/bin/install.sh"|"$BOOT_PROXY") mode=755;; "$PREVIOUS/"*) mode=600;; esac
        transaction_change "$relative" "${PLAN[$relative]}" "$mode"
    done
    if ((regenerate)); then
        "${generator[@]}" "$CANDIDATE" || die "GRUB configuration generation failed"
        if [[ $ACTION != uninstall ]]; then
            # Staging generators need the same transformation as the live proxy.
            local -a helper_options=()
            if [[ $THEME == ayanami || $THEME == seele ]]; then helper_options+=(--numbered); fi
            bash "$ROOT/$BOOT_HELPER" filter "$CANDIDATE" --root "$ROOT" "${helper_options[@]}" > "$WORK/console-config" || die 'Console handoff generation failed'
            cat -- "$WORK/console-config" > "$CANDIDATE"
        fi
        "$checker" "$CANDIDATE" || die "Generated GRUB configuration failed its syntax check"
        if [[ ! -s $CANDIDATE ]] || ! grep -q '[^[:space:]]' "$CANDIDATE"; then die 'Configuration generator produced an empty file'; fi
        if [[ $ACTION == uninstall ]]; then
            if grep -qF '# Evangelion exact-mode loader' "$CANDIDATE"; then die 'Generated config still contains the Evangelion loader'; fi
        else
            tail -n +3 "$ROOT/$HOOK" > "$WORK/expected-loader"
            record contains "$CANDIDATE" "$WORK/expected-loader" || die 'Generated config omitted or changed the Evangelion loader'
        fi
        transaction_change "$BACKUP" "$ROOT/$CONFIG" 600
        transaction_change "$CONFIG" "$CANDIDATE"
    fi
    for relative in "$STATE" "$MANAGER"; do
        if [[ -v PLAN[$relative] ]]; then transaction_change "$relative" "${PLAN[$relative]}" 600; fi
    done
    TRANSACTION=0
    remove_empty_owned_dirs
    case $ACTION in
        setup) printf 'Evangelion manager installed. Run sudo eva to select a theme.\n';;
        install) printf 'Installation complete.\n';;
        rollback) printf 'Previous Evangelion choice restored.\n';;
        uninstall) printf 'Evangelion removed; prior settings restored.\n';;
    esac
}

init_workspace() {
    need awk; need sha256sum; need flock
    ROOT=$(realpath -e -- "$ROOT")
    [[ -d $ROOT ]] || die '--root must be an existing directory'
    SOURCE=$(realpath -m -- "$SOURCE")
    load_catalog
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/eva-XXXXXXXX")
    trap cleanup EXIT
    mkdir -- "$WORK/new" "$WORK/old"
    trap 'exit 130' INT
    trap 'exit 143' TERM
    trap 'exit 129' HUP
}

run_operation() {
    local lock_path
    if ((!DRY_RUN)); then
        lock_path=$(safe_path "$ROOT" etc)
        exec {EVA_LOCK}< "$lock_path"
        flock -n "$EVA_LOCK" || die 'Another Evangelion operation is running'
    fi
    plan_changes
    prune_plan
    if ((DRY_RUN || !QUIET)); then display_plan; fi
    if ((DRY_RUN)); then printf 'Dry run only; configuration generation and boot behavior were not tested.\n'; else apply_changes; fi
}

# The backend entry is useful for staged validation without installing a catalog.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    exec "$EVA_REPO/bin/eva" --backend "$@"
fi
