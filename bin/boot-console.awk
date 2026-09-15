# SPDX-License-Identifier: Apache-2.0
# Tokenize GRUB as data, preserving source spans, quoting and boot arguments.

BEGIN {
    root = ARGV[1]
    numbered = ARGV[2]
    helper = ARGV[3]
    delete ARGV[1]
    delete ARGV[2]
    delete ARGV[3]
    marker = "# Evangelion console handoff v1"
    split("quiet splash rhgb loglevel systemd.show_status rd.systemd.show_status rd.udev.log_level udev.log_level vt.global_cursor_default plymouth.enable rd.plymouth disablehooks", keys, " ")
    for (i in keys) {
        display[keys[i]] = 1
    }
    visible = "loglevel=7 systemd.show_status=1 rd.systemd.show_status=1 rd.udev.log_level=info udev.log_level=info vt.global_cursor_default=1 plymouth.enable=0 rd.plymouth=0"
    RS = "^$"
    if ((getline source) < 0) {
        fail("Cannot read generated menu.")
    }
    result = transform(source)
    if (numbered == 1) {
        result = number_entries(result)
    }
    printf "%s", result
    exit
}

function add_token(start, end, raw, val, kind, dynamic)
{
    nt++
    ts[nt] = start
    te[nt] = end
    tr[nt] = raw
    tv[nt] = val
    tk[nt] = kind
    td[nt] = dynamic
}

function apply(text, i, j, k, tmp, order)
{
    for (i = 1; i <= nc; i++) {
        order[i] = i
    }
    for (i = 2; i <= nc; i++) {
        tmp = order[i]
        j = i - 1
        while (j > 0 && cs[order[j]] < cs[tmp]) {
            order[j + 1] = order[j]
            j--
        }
        order[j + 1] = tmp
    }
    for (i = 1; i <= nc; i++) {
        k = order[i]
        text = substr(text, 1, cs[k] - 1) cr[k] substr(text, ce[k])
    }
    return text
}

function arguments(first, last, i, n)
{
    na = 0
    for (i = first; i <= last; i++) {
        n = ++na
        ar[n] = tr[i]
        av[n] = tv[i]
        ad[n] = td[i]
    }
}

function change(start, end, replacement)
{
    nc++
    cs[nc] = start
    ce[nc] = end
    cr[nc] = replacement
}

function fail(message)
{
    print("eva: Console menu generation failed: " message) > "/dev/stderr"
    exit 1
}

function number_entries(text, i, pending, depth, level, command_start, token, end, j, badge, found)
{
    tokenize(text)
    nc = 0
    depth = 0
    level = 1
    counts[level] = 0
    pending = ""
    command_start = 1
    for (i = 1; i <= nt; i++) {
        token = td[i] ? "" : tv[i]
        if (tk[i] == "{") {
            block[++depth] = pending
            if (pending == "submenu") {
                counts[++level] = 0
            }
            pending = ""
            command_start = 1
            continue
        }
        if (tk[i] == "}") {
            if (block[depth--] == "submenu") {
                level--
            }
            command_start = 1
            continue
        }
        if (tk[i] == "\n" || tk[i] == ";") {
            command_start = 1
            continue
        }
        if (command_start && token ~ /^(if|elif|then|else|do|!)$/) {
            continue
        }
        if (command_start && token ~ /^(menuentry|submenu)$/) {
            pending = token
            counts[level]++
            end = i + 1
            while (end <= nt && tk[end] == "word") {
                end++
            }
            badge = counts[level] <= 99 ? sprintf("--class evangelion-index-%02d", counts[level]) : ""
            found = 0
            for (j = i + 1; j < end; j++) {
                if (! td[j] && tv[j] == "--class" && j + 1 < end && ! td[j + 1] && tv[j + 1] ~ /^evangelion-index-[0-9][0-9]$/) {
                    change(ts[j], te[j + 1], ! found ? badge : "")
                    found = 1
                    j++
                }
            }
            if (badge != "" && ! found) {
                change(te[i], te[i], " " badge)
            }
        }
        command_start = 0
    }
    return apply(text)
}

function quote_grub(s, i, c, out)
{
    out = "'"
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        out = out (c == "'" ? "'\\''" : c)
    }
    return (out "'")
}

function tokenize(text, i, start, c, value, q, dynamic, end, nextc)
{
    nt = 0
    i = 1
    while (i <= length(text)) {
        c = substr(text, i, 1)
        if (substr(text, i, 2) == "\\\n") {
            i += 2
            continue
        }
        if (c ~ /^[ \t\r]$/) {
            i++
            continue
        }
        if (c == "#") {
            while (i <= length(text) && substr(text, i, 1) != "\n") {
                i++
            }
            continue
        }
        start = i
        if (c ~ /^[\n;{}]$/) {
            add_token(i, i + 1, c, c, c, 0)
            i++
            continue
        }
        value = ""
        q = ""
        dynamic = 0
        while (i <= length(text)) {
            c = substr(text, i, 1)
            if (q == "'") {
                if (c == "'") {
                    q = ""
                } else {
                    value = value c
                }
                i++
                continue
            }
            if (c == "\\" && i < length(text)) {
                nextc = substr(text, i + 1, 1)
                if (nextc != "\n") {
                    value = value nextc
                }
                i += 2
                continue
            }
            if (q == "\"" && c == "\"") {
                q = ""
                i++
                continue
            }
            if (q == "" && (c == "'" || c == "\"")) {
                q = c
                i++
                continue
            }
            if (c == "$") {
                dynamic = 1
                if (substr(text, i, 2) == "${") {
                    end = index(substr(text, i + 2), "}")
                    if (! end) {
                        fail("Unclosed GRUB variable expansion.")
                    }
                    end = i + 1 + end
                    value = value substr(text, i, end - i + 1)
                    i = end + 1
                    continue
                }
            }
            if (q == "" && c ~ /^[ \t\r\n;{}]$/) {
                break
            }
            value = value c
            i++
        }
        if (q != "") {
            fail("Unclosed GRUB quotation.")
        }
        add_token(start, i, substr(text, start, i - start), value, "word", dynamic)
    }
}

function transform(text, i, pending, depth, command_start, entry_count, token, j, indent, start, rest, handoff, end, first, path_index, path, params, mode, k, in_entry, existing)
{
    tokenize(text)
    nc = 0
    depth = 0
    pending = ""
    command_start = 1
    entry_count = 0
    for (i = 1; i <= nt; i++) {
        token = td[i] ? "" : tv[i]
        if (tk[i] == "{") {
            block[++depth] = (pending != "" ? pending : "block")
            if (pending == "menuentry") {
                start = ts[i]
                while (start > 1 && substr(text, start - 1, 1) != "\n") {
                    start--
                }
                rest = substr(text, start)
                match(rest, /^[ \t]*/)
                indent = substr(rest, 1, RLENGTH) "    "
                handoff = "\n" indent marker "\n" indent "terminal_output console\n" indent "clear\n" indent "echo \"Starting $1...\"\n"
                rest = substr(text, te[i])
                existing = "^\n[ \t]*# Evangelion console handoff v1\n[ \t]*terminal_output console\n[ \t]*clear\n[ \t]*echo \"Starting \\$1\\.\\.\\.\"\n"
                if (rest !~ existing) {
                    change(te[i], te[i], handoff)
                }
                entry_count++
            }
            pending = ""
            command_start = 1
            continue
        }
        if (tk[i] == "}") {
            if (! depth) {
                fail("Unbalanced GRUB block.")
            }
            depth--
            command_start = 1
            continue
        }
        if (tk[i] == "\n" || tk[i] == ";") {
            command_start = 1
            continue
        }
        if (command_start && token ~ /^(if|elif|then|else|do|!)$/) {
            continue
        }
        if (command_start && token ~ /^(menuentry|submenu|function)$/) {
            pending = token
        }
        if (command_start && token == "blscfg") {
            fail("Runtime BLS menus are not supported by console handoff. Use generated GRUB menu entries.")
        }
        in_entry = 0
        for (k = 1; k <= depth; k++) {
            if (block[k] == "menuentry") {
                in_entry = 1
            }
        }
        if (command_start && in_entry && token ~ /^(linux|linuxefi|linux16|chainloader)$/) {
            end = i + 1
            while (end <= nt && tk[end] == "word") {
                end++
            }
            first = i + 1
            if (first == end) {
                fail(token " has no boot image.")
            }
            path_index = first + (! td[first] && tv[first] == "--force")
            if (path_index >= end) {
                fail("chainloader --force has no boot image.")
            }
            arguments(path_index + 1, end - 1)
            mode = "override"
            if (token == "chainloader") {
                mode = td[path_index] ? "" : uki(tv[path_index])
                if (mode == "blocked") {
                    print("eva: EFI console enabled; Secure Boot state prevents a verified UKI command-line override.") > "/dev/stderr"
                }
                if (mode == "override" && ! na) {
                    uki_arguments(embedded)
                }
            }
            if (mode == "override") {
                change(ts[i], te[end - 1], substr(text, ts[i], te[path_index] - ts[i]) " " visible_arguments())
            }
        }
        command_start = 0
    }
    if (depth || pending != "") {
        fail("Unclosed GRUB block.")
    }
    return (entry_count ? apply(text) : text)
}

function uki(path, cmd, line, status, mode, text, first, previous_rs)
{
    cmd = "bash " quote_grub(helper) " uki-info " quote_grub(root) " " quote_grub(path)
    first = 1
    mode = ""
    text = ""
    previous_rs = RS
    RS = "\n"
    while ((cmd | getline line) > 0) {
        if (first) {
            mode = line
            first = 0
        } else {
            text = text line "\n"
        }
    }
    status = close(cmd)
    RS = previous_rs
    if (status) {
        fail("Cannot inspect chainloaded EFI image.")
    }
    embedded = text
    return mode
}

function uki_arguments(text, i, start, c, quoted, raw)
{
    na = 0
    start = 0
    quoted = 0
    text = text " "
    for (i = 1; i <= length(text); i++) {
        c = substr(text, i, 1)
        if (! start) {
            if (c ~ /^[[:space:]]$/) {
                continue
            }
            start = i
        }
        if (c == "\"") {
            quoted = ! quoted
        }
        if (c ~ /^[[:space:]]$/ && ! quoted) {
            raw = substr(text, start, i - start)
            na++
            ar[na] = quote_grub(raw)
            gsub(/"/, "", raw)
            av[na] = raw
            ad[na] = 0
            start = 0
        }
    }
    if (quoted) {
        fail("Unclosed quotation in the embedded kernel command line.")
    }
}

function visible_arguments(i, v, key, disabled, console, kept, raw, n, hooks, j, hooklist, found)
{
    kept = ""
    disabled = ""
    console = 0
    for (i = 1; i <= na; i++) {
        v = av[i]
        raw = ar[i]
        if (ad[i]) {
            sub(/^"+/, "", raw)
            if (index(raw, "disablehooks=") == 1) {
                disabled = ar[i]
                if (substr(disabled, length(disabled) - 8) != ",plymouth") {
                    disabled = disabled ",plymouth"
                }
            } else {
                kept = kept ar[i] " "
            }
            console = console || index(raw, "console=") == 1
            continue
        }
        key = v
        sub(/=.*/, "", key)
        if (key == "disablehooks") {
            sub(/^[^=]*=?/, "", v)
            n = split(v, hooks, ",")
            hooklist = ""
            found = 0
            for (j = 1; j <= n; j++) {
                if (hooks[j] != "") {
                    hooklist = hooklist (hooklist != "" ? "," : "") hooks[j]
                    if (hooks[j] == "plymouth") {
                        found = 1
                    }
                }
            }
            if (! found) {
                hooklist = hooklist (hooklist != "" ? "," : "") "plymouth"
            }
            disabled = "disablehooks=" quote_grub(hooklist)
        }
        if (! (key in display)) {
            kept = kept ar[i] " "
        }
        console = console || key == "console"
    }
    if (! console) {
        kept = kept "console=tty0 "
    }
    return (kept visible " " (disabled != "" ? disabled : "disablehooks='plymouth'"))
}
