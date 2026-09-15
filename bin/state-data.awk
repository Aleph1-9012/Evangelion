# SPDX-License-Identifier: Apache-2.0
# Read installation records as JSON data. Never evaluate their contents as shell.

BEGIN {
    for (i = 1; i < ARGC; i++) {
        args[i] = ARGV[i]
    }
    for (i = 1; i < ARGC; i++) {
        delete ARGV[i]
    }
    op = args[1]
    # These operations read files directly so final newlines stay intact.
    if (op == "newline") {
        s = read_file(args[2])
        print (length(s) > 0 && substr(s, length(s)) != "\n" ? "true" : "false")
        exit
    }
    if (op == "contains") {
        exit (index(read_file(args[2]), read_file(args[3])) ? 0 : 1)
    }
    if (op == "hash-map") {
        id = node("object", "")
        while ((getline line) > 0) {
            n = split(line, parts, "\t")
            expect(n == 2 && safe_relative(parts[1]) && is_hash(parts[2]), "Invalid hash record")
            put(id, parts[1], node("string", parts[2]))
        }
        print encode(id)
        exit
    }
    if (op == "write-state") {
        work = args[2]
        old = parse(read_file(work "/old-state.json"))
        id = node("object", "")
        put(id, "version", node("number", "3"))
        put(id, "theme", node("string", args[3]))
        put(id, "profile", node("string", args[4]))
        put(id, "gfxmode", node("string", args[5]))
        put(id, "hook_hash", node("string", args[6]))
        put(id, "added_newline", node("boolean", args[7]))
        put(id, "block", node("string", read_file(work "/block")))
        put(id, "files", parse(read_file(work "/files.json")))
        put(id, "boot_files", parse(read_file(work "/boot-files.json")))
        put(id, "previous", parse(read_file(work "/previous.json")))
        if (jt[old] != "null") {
            prior = field(old, "prior_setting_lines")
        } else {
            prior = node("array", "")
            n = split(read_file(work "/base-defaults"), lines, "\n")
            for (i = 1; i <= n; i++) {
                if (lines[i] ~ /^[ \t]*(GRUB_THEME|GRUB_FONT|GRUB_GFXMODE|GRUB_TIMEOUT_STYLE)[ \t]*=/) {
                    put(prior, jl[prior] + 0, node("string", lines[i]))
                }
            }
        }
        put(id, "prior_setting_lines", prior)
        print encode(id)
        exit
    }
    RS = "^$"
    getline input
    id = parse(input)
    if (op == "get") {
        result = field(id, args[2])
        if (! result || jt[result] == "null") {
            printf "%s", args[3]
        } else if (jt[result] == "object" || jt[result] == "array") {
            print encode(result)
        } else {
            printf "%s", jv[result]
        }
    } else if (op == "canonical") {
        print encode(id)
    } else if (op == "pairs") {
        pairs(args[2] != "" ? field(id, args[2]) : id)
    } else if (op == "hashes") {
        hash_object(id)
    } else if (op == "choice") {
        choice(id, args[2])
    } else if (op == "manager") {
        expect(jt[id] == "object" && jt[field(id, "version")] == "number" && value(id, "version") == 1, "Invalid manager record")
        hash_object(field(id, "files"))
    } else if (op == "wrap-manager") {
        hash_object(id)
        result = node("object", "")
        put(result, "version", node("number", "1"))
        put(result, "files", id)
        print encode(result)
    } else if (op == "catalog") {
        expect(jt[id] == "object" && jt[field(id, "version")] == "number" && value(id, "version") == 1 && jt[field(id, "themes")] == "array", "Invalid theme catalog")
        themes = field(id, "themes")
        for (i = 1; i <= jl[themes]; i++) {
            entry = field(themes, i - 1)
            theme = value(entry, "id")
            name = value(entry, "name")
            expect(jt[field(entry, "id")] == "string" && theme ~ /^[a-z][a-z0-9_-]*$/ && ! (theme in seen) && jt[field(entry, "name")] == "string" && name != "" && name !~ /[[:cntrl:]]/, "Invalid theme catalog entry")
            seen[theme] = 1
            output = output theme "\t" name "\n"
        }
        printf "%s", output
    } else if (op == "readiness") {
        canvas = field(id, "canvas")
        split(args[4], size, "x")
        expect(jt[id] == "object" && jt[field(id, "ready")] == "boolean" && value(id, "ready") == "true" && jt[field(id, "theme")] == "string" && jt[field(id, "profile")] == "string" && value(id, "theme") == args[2] && value(id, "profile") == args[3] && jt[canvas] == "array" && jl[canvas] == 2 && jt[field(canvas, 0)] == "number" && jt[field(canvas, 1)] == "number" && jv[field(canvas, 0)] == size[1] && jv[field(canvas, 1)] == size[2], "Invalid readiness record")
        hash_object(field(id, "sha256"))
        expect(jl[field(id, "sha256")] > 0, "Empty readiness record")
        print encode(field(id, "sha256"))
    } else if (op == "state") {
        expect(jt[id] == "object" && jt[field(id, "version")] == "number" && value(id, "version") ~ /^[123]$/ && jt[field(id, "block")] == "string" && (index(value(id, "block"), args[2] "\n") == 1 || index(value(id, "block"), args[3] "\n") == 1) && is_hash(value(id, "hook_hash")), "Unsupported or damaged ownership manifest")
        prior = field(id, "prior_setting_lines")
        expect(jt[prior] == "array", "Invalid original setting lines")
        for (i = 1; i <= jl[prior]; i++) {
            expect(jt[field(prior, i - 1)] == "string", "Invalid original setting line")
        }
        added = field(id, "added_newline")
        expect(! added || jt[added] == "boolean", "Invalid newline record")
    } else if (op == "grub-dir") {
        files = field(id, "files")
        hash_object(files)
        for (i = 1; i <= jl[files]; i++) {
            k = jo[files, i]
            expect(k ~ /^boot\/grub2?\/themes\/evangelion\//, "Invalid GRUB ownership path")
            split(k, parts, "/")
            dir = parts[1] "/" parts[2]
            expect(! recorded || recorded == dir, "Ambiguous GRUB ownership paths")
            recorded = dir
        }
        expect(recorded != "", "Missing GRUB ownership paths")
        print recorded
    } else if (op == "snapshot") {
        files = field(id, "files")
        result = node("object", "")
        if (files) {
            hash_object(files)
            for (i = 1; i <= jl[files]; i++) {
                k = jo[files, i]
                expect(index(k, args[2]) == 1, "Invalid snapshot prefix")
                put(result, args[3] substr(k, length(args[2]) + 1), field(files, k))
            }
        }
        print encode(result)
    } else if (op == "same-choice") {
        expected = parse(read_file(args[5]))
        exit ! (value(id, "theme") == args[2] && value(id, "profile") == args[3] && value(id, "gfxmode") == args[4] && encode(field(id, "files")) == encode(expected))
    } else if (op == "choice-record") {
        result = node("object", "")
        split("theme profile gfxmode files", keys, " ")
        for (i = 1; i <= 4; i++) {
            put(result, keys[i], field(id, keys[i]))
        }
        print encode(result)
    } else if (op == "strip-block") {
        text = read_file(args[2])
        starts = occurrences(text, args[3] "\n") + occurrences(text, args[4] "\n")
        ends = occurrences(text, args[5] "\n")
        if (jt[id] == "null") {
            expect(! starts && ! ends, "Managed block exists without an ownership manifest")
        } else {
            block = value(id, "block")
            start = index(text, block)
            expect(starts == 1 && ends == 1 && start > 0, "Managed defaults were edited; restore the recorded block before continuing")
            suffix = substr(text, start + length(block))
            end = start - 1
            if (value(id, "added_newline") == "true" && end > 0 && substr(text, end, 1) == "\n" && (suffix == "" || substr(suffix, 1, 1) == "\n")) {
                end--
            }
            text = substr(text, 1, end) suffix
        }
        printf "%s", text
    } else {
        fail("Unknown record operation: " op)
    }
    exit
}

function choice(id, runtime)
{
    expect(jt[id] == "object" && jt[field(id, "gfxmode")] == "string" && jt[field(id, "theme")] == "string" && jt[field(id, "profile")] == "string", "Invalid theme-choice record")
    hash_object(field(id, "files"))
    expect(field(field(id, "files"), runtime "/theme.txt"), "Theme choice has no theme.txt")
}

function encode(id, i, k, out, keys, n, j, tmp)
{
    if (! id || jt[id] == "null") {
        return "null"
    }
    if (jt[id] == "string") {
        return json_quote(jv[id])
    }
    if (jt[id] != "object" && jt[id] != "array") {
        return jv[id]
    }
    n = jl[id]
    for (i = 1; i <= n; i++) {
        keys[i] = jo[id, i]
    }
    if (jt[id] == "object") {
        for (i = 2; i <= n; i++) {
            tmp = keys[i]
            j = i - 1
            while (j > 0 && keys[j] > tmp) {
                keys[j + 1] = keys[j]
                j--
            }
            keys[j + 1] = tmp
        }
    }
    out = jt[id] == "object" ? "{" : "["
    for (i = 1; i <= n; i++) {
        k = keys[i]
        out = out (i > 1 ? "," : "") (jt[id] == "object" ? json_quote(k) ":" : "") encode(jc[id, k])
    }
    return (out (jt[id] == "object" ? "}" : "]"))
}

function expect(condition, message)
{
    if (! condition) {
        fail(message)
    }
}

function fail(message)
{
    print("eva: " message) > "/dev/stderr"
    exit 1
}

function field(id, key)
{
    return jc[id, key]
}

function hash_object(id, i, k)
{
    expect(jt[id] == "object", "Expected asset hash map")
    for (i = 1; i <= jl[id]; i++) {
        k = jo[id, i]
        expect(safe_relative(k) && jt[jc[id, k]] == "string" && is_hash(jv[jc[id, k]]), "Unsafe asset hash entry")
    }
}

function hex4(i, c, n)
{
    n = 0
    for (i = 0; i < 4; i++) {
        c = index("0123456789abcdef", tolower(substr(js, jp++, 1)))
        if (! c) {
            fail("Invalid JSON Unicode escape")
        }
        n = n * 16 + c - 1
    }
    return n
}

function is_hash(text)
{
    return (length(text) == 64 && text !~ /[^a-f0-9]/)
}

function json_quote(value, i, c, out, n)
{
    out = "\""
    for (i = 1; i <= length(value); i++) {
        c = substr(value, i, 1)
        if (c == "\\" || c == "\"") {
            out = out "\\" c
        } else if (c == "\n") {
            out = out "\\n"
        } else if (c == "\r") {
            out = out "\\r"
        } else if (c == "\t") {
            out = out "\\t"
        } else if (c ~ /[[:cntrl:]]/) {
            for (n = 1; n < 32; n++) {
                if (c == sprintf("%c", n)) {
                    break
                }
            }
            out = out sprintf("\\u%04x", n == 32 ? 127 : n)
        } else {
            out = out c
        }
    }
    return (out "\"")
}

function node(type, value, id)
{
    id = ++jn
    jt[id] = type
    jv[id] = value
    return id
}

function occurrences(text, needle, n, p)
{
    n = 0
    while (p = index(text, needle)) {
        n++
        text = substr(text, p + length(needle))
    }
    return n
}

function pairs(id, i, k)
{
    hash_object(id)
    for (i = 1; i <= jl[id]; i++) {
        k = jo[id, i]
        print k "\t" jv[jc[id, k]]
    }
}

function parse(text, id)
{
    js = text
    jp = 1
    id = parse_value(0)
    skip_space()
    if (jp <= length(js)) {
        fail("Extra data after JSON record")
    }
    return id
}

function parse_value(depth, id, c, key, child, literal)
{
    if (depth > 64) {
        fail("Installation record nesting is too deep")
    }
    skip_space()
    c = substr(js, jp, 1)
    if (c == "\"") {
        return node("string", string_value())
    }
    if (c == "{" || c == "[") {
        id = node(c == "{" ? "object" : "array", "")
        jp++
        skip_space()
        if (substr(js, jp, 1) == (c == "{" ? "}" : "]")) {
            jp++
            return id
        }
        while (1) {
            skip_space()
            if (c == "{") {
                key = string_value()
                skip_space()
                if (substr(js, jp++, 1) != ":") {
                    fail("Expected JSON colon")
                }
                if ((id SUBSEP key) in jc) {
                    fail("Duplicate JSON key")
                }
            } else {
                key = jl[id] + 0
            }
            child = parse_value(depth + 1)
            put(id, key, child)
            skip_space()
            literal = substr(js, jp++, 1)
            if (literal == (c == "{" ? "}" : "]")) {
                return id
            }
            if (literal != ",") {
                fail("Expected JSON separator")
            }
        }
    }
    if (match(substr(js, jp), /^(true|false|null)/)) {
        literal = substr(js, jp, RLENGTH)
        jp += RLENGTH
        return node(literal == "null" ? "null" : "boolean", literal)
    }
    if (match(substr(js, jp), /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/)) {
        literal = substr(js, jp, RLENGTH)
        jp += RLENGTH
        return node("number", literal)
    }
    fail("Invalid JSON value")
}

function put(id, key, child)
{
    if (! ((id SUBSEP key) in jc)) {
        jo[id, ++jl[id]] = key
    }
    jc[id, key] = child
}

function read_file(path, value, status, previous)
{
    previous = RS
    RS = "^$"
    status = (getline value < path)
    close(path)
    RS = previous
    if (status < 0) {
        fail("Cannot read " path)
    }
    return value
}

function safe_relative(text, n, parts, i)
{
    if (text !~ /^[A-Za-z0-9_.\/-]+$/ || substr(text, 1, 1) == "/") {
        return 0
    }
    n = split(text, parts, "/")
    for (i = 1; i <= n; i++) {
        if (parts[i] == "" || parts[i] == "." || parts[i] == "..") {
            return 0
        }
    }
    return 1
}

function skip_space()
{
    while (substr(js, jp, 1) ~ /^[ \t\r\n]$/) {
        jp++
    }
}

function string_value(out, c, n, low)
{
    if (substr(js, jp++, 1) != "\"") {
        fail("Expected JSON string")
    }
    out = ""
    while (jp <= length(js)) {
        c = substr(js, jp++, 1)
        if (c == "\"") {
            return out
        }
        if (c == "\\") {
            c = substr(js, jp++, 1)
            if (c == "u") {
                n = hex4()
                if (n >= 55296 && n <= 56319) {
                    if (substr(js, jp, 2) != "\\u") {
                        fail("Missing JSON surrogate pair")
                    }
                    jp += 2
                    low = hex4()
                    if (low < 56320 || low > 57343) {
                        fail("Invalid JSON surrogate pair")
                    }
                    n = 65536 + (n - 55296) * 1024 + low - 56320
                } else if (n >= 56320 && n <= 57343) {
                    fail("Invalid JSON surrogate")
                }
                if (! n) {
                    fail("NUL is not supported in installation records")
                }
                out = out utf8(n)
            } else if (c == "\"" || c == "\\" || c == "/") {
                out = out c
            } else if (c == "b") {
                out = out "\b"
            } else if (c == "f") {
                out = out "\f"
            } else if (c == "n") {
                out = out "\n"
            } else if (c == "r") {
                out = out "\r"
            } else if (c == "t") {
                out = out "\t"
            } else {
                fail("Invalid JSON escape")
            }
        } else {
            if (c ~ /[[:cntrl:]]/ && c != sprintf("%c", 127)) {
                fail("Control character in JSON string")
            }
            out = out c
        }
    }
    fail("Unclosed JSON string")
}

function utf8(n)
{
    if (n < 128) {
        return sprintf("%c", n)
    }
    if (n < 2048) {
        return sprintf("%c%c", 192 + int(n / 64), 128 + n % 64)
    }
    if (n < 65536) {
        return sprintf("%c%c%c", 224 + int(n / 4096), 128 + int(n / 64) % 64, 128 + n % 64)
    }
    return sprintf("%c%c%c%c", 240 + int(n / 262144), 128 + int(n / 4096) % 64, 128 + int(n / 64) % 64, 128 + n % 64)
}

function value(id, key)
{
    return jv[jc[id, key]]
}
