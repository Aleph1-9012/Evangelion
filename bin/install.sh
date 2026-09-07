#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Aleph1-9012
# Shared installation functions for eva. State stays compatible with v1.0.0.

set -Eeuo pipefail
export LC_ALL=C

EVA_REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DEFAULTS=etc/default/grub
CONFIG=boot/grub/grub.cfg
RUNTIME=boot/grub/themes/evangelion
HOOK=etc/grub.d/99_evangelion
STATE=var/lib/evangelion-grub/state.json
BACKUP=var/lib/evangelion-grub/grub.cfg.previous
LIBRARY=usr/local/share/evangelion
COMMAND=usr/local/bin/eva
MANAGER=var/lib/evangelion-grub/manager.json
PREVIOUS=var/lib/evangelion-grub/previous
BEGIN='# BEGIN EVANGELION GRUB (managed; use install.sh --uninstall)'
LEGACY_BEGIN='# BEGIN EVANGELION GRUB (managed; use uninstall.sh)'
END='# END EVANGELION GRUB'
THEMES=(eva01 wunder eva02 ramiel)
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

safe_path() {
    local base=$1 relative=$2 part cursor=$1
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
    local data=$1 prefix=$2 path value
    jq -e 'type == "object" and all(to_entries[]; (.value|type == "string") and (.value|test("^[a-f0-9]{64}$")))' <<< "$data" >/dev/null || die 'Unsafe ownership manifest'
    while IFS=$'\t' read -r path value; do
        [[ -n $path ]] || continue
        safe_path "$ROOT" "$path" >/dev/null
        [[ $path == "$prefix/"* || ( $prefix == "$LIBRARY" && $path == "$COMMAND" ) ]] || die "Unsafe ownership path: $path"
    done < <(jq -r 'to_entries[] | [.key,.value] | @tsv' <<< "$data")
}

validate_choice() {
    local data=$1 theme profile mode
    jq -e --arg path "$RUNTIME/theme.txt" 'type == "object" and (.files|type == "object") and (.files|has($path)) and (.gfxmode|type == "string")' <<< "$data" >/dev/null || die 'Invalid theme-choice record'
    theme=$(jq -r .theme <<< "$data"); profile=$(jq -r .profile <<< "$data"); mode=$(jq -r .gfxmode <<< "$data")
    case $theme in eva01|wunder|eva02|ramiel) ;; *) die 'Invalid theme-choice record';; esac
    mode_for "$profile" "$mode" >/dev/null
    validate_hashes "$(jq -c .files <<< "$data")" "$RUNTIME"
}

load_state() {
    local path
    STATE_DATA=null
    path=$(safe_path "$ROOT" "$STATE"); regular_or_absent "$path"
    if [[ -f $path ]]; then
        STATE_DATA=$(cat -- "$path")
        jq -e --arg begin "$BEGIN" --arg legacy "$LEGACY_BEGIN" '
            type == "object" and (.version == 1 or .version == 2) and
            (.block|type == "string") and (.block|startswith($begin+"\n") or startswith($legacy+"\n")) and
            (.hook_hash|type == "string") and (.hook_hash|test("^[a-f0-9]{64}$")) and
            (.prior_setting_lines|type == "array") and all(.prior_setting_lines[]; type == "string") and
            ((.added_newline // false)|type == "boolean")' <<< "$STATE_DATA" >/dev/null || die 'Unsupported or damaged ownership manifest'
        validate_choice "$STATE_DATA"
        if [[ $(jq -r '.previous != null' <<< "$STATE_DATA") == true ]]; then validate_choice "$(jq -c .previous <<< "$STATE_DATA")"; fi
    fi
}

load_manager() {
    local path
    MANAGER_DATA=null
    path=$(safe_path "$ROOT" "$MANAGER"); regular_or_absent "$path"
    if [[ -f $path ]]; then
        MANAGER_DATA=$(cat -- "$path")
        jq -e 'type == "object" and .version == 1' <<< "$MANAGER_DATA" >/dev/null || die 'Unsupported or damaged manager manifest'
        validate_hashes "$(jq -c .files <<< "$MANAGER_DATA")" "$LIBRARY"
    fi
}

font_name() {
    local file=$1 header offset=12 length tag size b0 b1 b2 b3
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
    local path relative name header line key value pattern suffix
    local -A names=() images=()
    local property='^[[:space:]]*([A-Za-z_][A-Za-z0-9_-]*)[[:space:]]*[:=][[:space:]]*(.*)$'
    local quoted='^"([^"]*)"' unquoted='^([^[:space:]#}]+)'
    [[ -v resources[$RUNTIME/theme.txt] ]] || die 'Ready theme is missing theme.txt'
    for path in "${!resources[@]}"; do
        case $path in
            *.pf2) name=$(font_name "${resources[$path]}") || die 'Invalid runtime font'; names["$name"]=1;;
            *.png)
                header=$(od -An -tx1 -N8 -- "${resources[$path]}" | tr -d ' \n')
                [[ $header == 89504e470d0a1a0a ]] || die "Runtime PNG has an invalid signature: $path"
                images["${path#"$RUNTIME/"}"]=1;;
        esac
    done
    ((${#images[@]} && ${#names[@]})) || die 'Ready theme needs PNG artwork and PF2 fonts'
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ $property ]] || continue
        key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
        if [[ $value =~ $quoted ]]; then value=${BASH_REMATCH[1]}; elif [[ $value =~ $unquoted ]]; then value=${BASH_REMATCH[1]}; else continue; fi
        case $key in
            desktop-image|file|center_bitmap|tick_bitmap)
                [[ -n $value && -v images[$value] ]] || die "Missing or unsupported theme image reference: $key=$value";;
            item_pixmap_style|selected_item_pixmap_style|menu_pixmap_style|scrollbar_frame|scrollbar_thumb|bar_style|highlight_style)
                [[ $value =~ ^[A-Za-z0-9_./-]+_\*\.png$ ]] || die "Unsupported styled-box reference: $value"
                pattern=${value/\*/c}
                [[ -v images[$pattern] ]] || die "Missing center slice: $value"
                for relative in "${!images[@]}"; do
                    # The generated styled-box reference is a validated glob.
                    # shellcheck disable=SC2053
                    if [[ $relative == $value ]]; then
                        suffix=${relative#"${value%\**}"}; suffix=${suffix%.png}
                        case $suffix in c|n|s|e|w|nw|ne|sw|se) ;; *) die "Invalid styled-box slice: $relative";; esac
                    fi
                done;;
            font|item_font|selected_item_font|title-font|message-font|terminal-font)
                [[ -n $value && -v names[$value] ]] || die "Theme font is not present in the packaged PF2 files: $value";;
        esac
    done < "${resources[$RUNTIME/theme.txt]}"
}

# Hash maps use JSON to retain the existing release's state format. jq parses
# records as data; neither the records nor GRUB defaults are executed as Shell.
hash_map() {
    local -n entries=$1
    local path digest
    for path in "${!entries[@]}"; do
        digest=$(sha "${entries[$path]}") || return 1
        printf '%s\t%s\n' "$path" "$digest"
    done |
        jq -Rn '[inputs | split("\t") | {key: .[0], value: .[1]}] | from_entries'
}

source_files() {
    local theme=$1 profile=$2 base ready native path relative hashes expected
    local -A assets=()
    FILES=()
    base=$(safe_path "$SOURCE" "$theme/$profile")
    ready=$(safe_path "$base" runtime-ready.json)
    [[ -f $ready ]] || die "Theme is unavailable: $theme/$profile has no readiness record"
    native=$(profile_mode "$profile")
    jq -e --arg theme "$theme" --arg profile "$profile" --arg mode "$native" '
        type == "object" and .ready == true and .theme == $theme and .profile == $profile and
        .canvas == ($mode|split("x")|map(tonumber)) and
        (.sha256|type == "object" and length > 0) and
        all(.sha256|to_entries[]; (.value|type == "string") and (.value|test("^[a-f0-9]{64}$")))' "$ready" >/dev/null || die "Invalid readiness record: $theme/$profile"
    while IFS= read -r relative; do safe_path "$base" "$relative" >/dev/null; done < <(jq -r '.sha256|keys[]' "$ready")
    while IFS= read -r -d '' path; do
        relative=${path#"$base/"}
        safe_path "$base" "$relative" >/dev/null
        [[ -f $path || -d $path ]] || die "Source contains a non-regular file: $path"
        [[ -f $path && $relative != runtime-ready.json ]] || continue
        # hash_map reads this array through a nameref.
        # shellcheck disable=SC2034
        assets["$relative"]=$path
        case $relative in theme.txt|*.png|fonts/*.pf2) FILES["$RUNTIME/$relative"]=$path;; esac
    done < <(find "$base" -mindepth 1 -print0)
    hashes=$(hash_map assets) || die 'Cannot hash theme assets'
    expected=$(jq -cS .sha256 "$ready")
    [[ $(jq -cS . <<< "$hashes") == "$expected" ]] || die "Runtime files differ from the readiness record; rebuild: $theme/$profile"
    validate_references FILES
}

plan_add() {
    local relative=$1 source=${2:-} path
    path=$(safe_path "$ROOT" "$relative"); regular_or_absent "$path"
    if [[ -z $source ]]; then
        PLAN["$relative"]=
    else
        NEXT_FILE=$((NEXT_FILE + 1))
        cp -- "$source" "$WORK/new/$NEXT_FILE"
        PLAN["$relative"]=$WORK/new/$NEXT_FILE
    fi
}

owned_changes() {
    local old=$1 removing=$3 relative current expected
    local -n desired=$2
    local -A union=()
    while IFS= read -r relative; do union["$relative"]=1; done < <(jq -r 'keys[]' <<< "$old")
    for relative in "${!desired[@]}"; do union["$relative"]=1; done
    for relative in "${!union[@]}"; do
        current=$(safe_path "$ROOT" "$relative"); regular_or_absent "$current"
        expected=$(jq -r --arg p "$relative" '.[$p] // empty' <<< "$old")
        if [[ -n $expected ]]; then
            if [[ -f $current && $(sha "$current") != "$expected" ]]; then
                if ((removing)); then printf 'Preserving modified file: /%s\n' "$relative"; continue; fi
                die "Refusing to overwrite a modified owned file: /$relative"
            fi
        elif [[ -e $current ]]; then die "Refusing to overwrite an unowned file: /$relative"
        fi
        plan_add "$relative" "${desired[$relative]:-}"
    done
}

plan_manager() {
    local removing=${1:-0} relative path theme profile base count=0 hashes
    local -A manager_files=()
    load_manager
    if ((!removing)); then
        for relative in bin/install.sh bin/eva LICENSE NOTICE.md docs/licenses/{space-mono,jetbrains-mono,six-caps,intel-one-mono,inter}/OFL.txt; do
            path=$(safe_path "$EVA_REPO" "$relative")
            [[ -f $path ]] || die "Missing package file: $relative"
            manager_files["$LIBRARY/$relative"]=$path
        done
        manager_files["$COMMAND"]=${manager_files[$LIBRARY/bin/eva]}
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
    owned_changes "$(jq -c '.files // {}' <<< "$MANAGER_DATA")" manager_files "$removing"
    if ((removing)); then plan_add "$MANAGER"; else
        hashes=$(hash_map manager_files)
        jq -Sn --argjson files "$hashes" '{version: 1, files: $files}' > "$WORK/manager.json"
        plan_add "$MANAGER" "$WORK/manager.json"
    fi
}

check_system() {
    local release identity
    release=$(realpath -e -- "$ROOT/etc/os-release") || die 'Missing OS identity file'
    [[ $ROOT == / || $release == "$ROOT/"* ]] || die 'The OS identity symlink points outside the staging root'
    identity=$(sed -nE "s/^ID=[\"']?([^\"']*)[\"']?$/\1/p" "$release")
    [[ $identity == arch ]] || die 'This installer currently supports Arch Linux (ID=arch) only'
}

strip_block() {
    jq -Rjs --arg begin "$BEGIN" --arg legacy "$LEGACY_BEGIN" --arg end "$END" --argjson state "$STATE_DATA" '
        (indices($begin+"\n")|length) + (indices($legacy+"\n")|length) as $starts |
        (indices($end+"\n")|length) as $ends |
        if $state == null then
            if $starts != 0 or $ends != 0 then error("Managed block exists without an ownership manifest") else . end
        else
            if $starts != 1 or $ends != 1 or (contains($state.block)|not) then error("Managed defaults were edited; restore the recorded block before continuing") else
                index($state.block) as $start | .[$start+($state.block|length):] as $suffix |
                if $state.added_newline and $start > 0 and .[$start-1:$start] == "\n" and ($suffix == "" or ($suffix|startswith("\n")))
                then .[:$start-1] + $suffix else .[:$start] + $suffix end
            end
        end' "$ROOT/$DEFAULTS" > "$WORK/base-defaults"
}

make_hook() {
    local mode=$1 path
    cat <<HEADER
#!/bin/sh
exec tail -n +3 "\$0"
# Evangelion exact-mode loader
terminal_output console
unset theme
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
        printf 'loadfont "$prefix/%s"\n' "${path#boot/grub/}"
    done < <(printf '%s\n' "${!FILES[@]}" | sort)
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
    local path relative expected old_files old_previous old_snapshot hashes previous newline mode
    # owned_changes reads these arrays through namerefs.
    # shellcheck disable=SC2034
    local -A snapshot=() empty=()
    check_system
    if [[ $ACTION == setup ]]; then plan_manager; return; fi
    load_state
    if [[ $ACTION == uninstall ]]; then
        plan_manager 1
        [[ $STATE_DATA != null ]] || return 0
    fi
    for relative in "$DEFAULTS" "$CONFIG" etc/grub.d/00_header; do
        path=$(safe_path "$ROOT" "$relative")
        [[ -f $path ]] || die "Existing GRUB installation required: /$relative"
    done
    strip_block
    old_files=$(jq -c '.files // {}' <<< "$STATE_DATA")
    old_previous=$(jq -c '.previous // null' <<< "$STATE_DATA")
    old_snapshot=$(jq -c --arg runtime "$RUNTIME/" --arg previous "$PREVIOUS/" '(.files // {}) | with_entries(.key |= ($previous + ltrimstr($runtime)))' <<< "$old_previous")
    path=$(safe_path "$ROOT" "$HOOK"); regular_or_absent "$path"
    if [[ $STATE_DATA != null ]]; then
        [[ -f $path && $(sha "$path") == "$(jq -r .hook_hash <<< "$STATE_DATA")" ]] || die 'The managed loader changed; restore it before continuing'
    else [[ ! -e $path ]] || die "Refusing to overwrite an unowned /$HOOK"; fi
    if [[ $ACTION == uninstall ]]; then
        plan_add "$DEFAULTS" "$WORK/base-defaults"
        plan_add "$HOOK"; plan_add "$STATE"
        owned_changes "$old_files" empty 1
        owned_changes "$old_snapshot" empty 1
        return
    fi
    if [[ $ACTION == rollback ]]; then
        [[ $old_previous != null ]] || die 'No previous Evangelion choice is saved; use uninstall to restore the pre-Evangelion appearance'
        THEME=$(jq -r .theme <<< "$old_previous"); PROFILE=$(jq -r .profile <<< "$old_previous"); mode=$(jq -r .gfxmode <<< "$old_previous")
        FILES=()
        while IFS=$'\t' read -r relative expected; do
            path=$(safe_path "$ROOT" "$PREVIOUS/${relative#"$RUNTIME/"}")
            [[ -f $path && $(sha "$path") == "$expected" ]] || die "Previous theme snapshot is missing or modified: $path"
            FILES["$relative"]=$path
        done < <(jq -r '.files|to_entries[]|[.key,.value]|@tsv' <<< "$old_previous")
        validate_references FILES
    else
        source_files "$THEME" "$PROFILE"
        mode=$(mode_for "$PROFILE" "$MODE" "$WORK/base-defaults")
    fi
    owned_changes "$old_files" FILES 0
    hashes=$(hash_map FILES)
    previous=$old_previous
    if [[ $STATE_DATA != null ]] && ! jq -e --arg theme "$THEME" --arg profile "$PROFILE" --arg mode "$mode" --argjson files "$hashes" '.theme == $theme and .profile == $profile and .gfxmode == $mode and .files == $files' <<< "$STATE_DATA" >/dev/null; then
        while IFS=$'\t' read -r relative expected; do
            path=$(safe_path "$ROOT" "$relative")
            [[ -f $path && $(sha "$path") == "$expected" ]] || die "Current theme cannot be saved for rollback: /$relative is missing or modified"
            # shellcheck disable=SC2034
            snapshot["$PREVIOUS/${relative#"$RUNTIME/"}"]=$path
        done < <(jq -r 'to_entries[]|[.key,.value]|@tsv' <<< "$old_files")
        owned_changes "$old_snapshot" snapshot 0
        previous=$(jq -c '{theme,profile,gfxmode,files}' <<< "$STATE_DATA")
    fi
    printf '%s\n' "$BEGIN" '# The late loader selects the theme only after the exact mode succeeds.' 'GRUB_THEME=""' 'GRUB_FONT=""' "GRUB_GFXMODE=\"$mode\"" 'GRUB_TIMEOUT_STYLE="menu"' "$END" > "$WORK/block"
    newline=$(jq -Rs 'length > 0 and (endswith("\n")|not)' "$WORK/base-defaults")
    cat -- "$WORK/base-defaults" > "$WORK/defaults"
    if [[ $newline == true ]]; then printf '\n' >> "$WORK/defaults"; fi
    cat -- "$WORK/block" >> "$WORK/defaults"
    make_hook "$mode" > "$WORK/hook"
    jq -Sn --arg theme "$THEME" --arg profile "$PROFILE" --arg mode "$mode" --rawfile block "$WORK/block" --rawfile base "$WORK/base-defaults" --argjson newline "$newline" --argjson previous "$previous" --argjson files "$hashes" --arg hook_hash "$(sha "$WORK/hook")" --argjson old "$STATE_DATA" '{
        version: 2, theme: $theme, profile: $profile, gfxmode: $mode, block: $block, added_newline: $newline,
        previous: $previous, files: $files, hook_hash: $hook_hash,
        prior_setting_lines: (if $old != null then $old.prior_setting_lines else [$base|scan("(?m)^\\s*(?:GRUB_THEME|GRUB_FONT|GRUB_GFXMODE|GRUB_TIMEOUT_STYLE)\\s*=.*$")] end)
    }' > "$WORK/state.json"
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
        for prefix in "$RUNTIME" "$PREVIOUS" "$LIBRARY"; do
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
    local relative mode regenerate=0 path
    local -a generator=()
    ((${#PLAN[@]})) || { printf 'Already in the requested state; no changes.\n'; return; }
    [[ $ROOT != / || $EUID == 0 ]] || die 'Host installation requires root; inspect --dry-run before running with sudo'
    if needs_generation; then
        regenerate=1; need grub-script-check
        if [[ $ROOT != / ]]; then
            [[ -n $GENERATOR ]] || die 'A staging root requires --generator EXECUTABLE; host grub-mkconfig is never run against a stage'
            generator=("$(realpath -e -- "$GENERATOR")" "$ROOT")
        else
            [[ -z $GENERATOR ]] || die '--generator is available only with a staging --root'
            need grub-mkconfig; generator=(grub-mkconfig -o)
        fi
        # Test the boot destination before changing defaults or runtime files.
        CANDIDATE=$(mktemp "$ROOT/boot/grub/.grub.cfg.evangelion-XXXXXX")
    fi
    TRANSACTION=1
    for relative in "${!PLAN[@]}"; do
        [[ $relative != "$STATE" && $relative != "$MANAGER" ]] || continue
        mode=
        case $relative in "$HOOK"|"$COMMAND"|"$LIBRARY/bin/eva"|"$LIBRARY/bin/install.sh") mode=755;; "$PREVIOUS/"*) mode=600;; esac
        transaction_change "$relative" "${PLAN[$relative]}" "$mode"
    done
    if ((regenerate)); then
        "${generator[@]}" "$CANDIDATE" || die "GRUB configuration generation failed"
        grub-script-check "$CANDIDATE" || die "Generated GRUB configuration failed its syntax check"
        if [[ ! -s $CANDIDATE ]] || ! grep -q '[^[:space:]]' "$CANDIDATE"; then die 'Configuration generator produced an empty file'; fi
        if [[ $ACTION == uninstall ]]; then
            if grep -qF '# Evangelion exact-mode loader' "$CANDIDATE"; then die 'Generated config still contains the Evangelion loader'; fi
        else
            tail -n +3 "$ROOT/$HOOK" > "$WORK/expected-loader"
            jq -en --rawfile expected "$WORK/expected-loader" --rawfile generated "$CANDIDATE" '$generated|contains($expected)' >/dev/null || die 'Generated config omitted or changed the Evangelion loader'
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
    need jq; need sha256sum; need flock
    ROOT=$(realpath -e -- "$ROOT")
    [[ -d $ROOT ]] || die '--root must be an existing directory'
    SOURCE=$(realpath -m -- "$SOURCE")
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
