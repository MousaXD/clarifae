# Edit audio_effects_conf by element instead of line. Keep OEM content, including
# effect proxies, existing apply order, comments and XInclude directives.
function fail() {
    invalid = 1
    exit 1
}
function attr(tag, name,    value) {
    if (!match(tag, "[[:space:]]" name "[[:space:]]*=[[:space:]]*(\"[^\"]*\"|'[^']*')")) return ""
    value = substr(tag, RSTART, RLENGTH)
    sub(/^[^=]*=[[:space:]]*/, "", value)
    return substr(value, 2, length(value) - 2)
}
function emit(text) {
    if (!discovering) printf "%s", text
}
function valid_uuid(uuid) {
    return length(uuid) == 36 && uuid ~ /^[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+-[0-9a-f]+$/ &&
           substr(uuid, 9, 1) == "-" && substr(uuid, 14, 1) == "-" &&
           substr(uuid, 19, 1) == "-" && substr(uuid, 24, 1) == "-"
}
function stock_metadata(tag, name,    effect, uuid, type) {
    if (depth == 2 && stack[2] == "libraries" && name == "library") {
        libraries[attr(tag, "name")] = attr(tag, "path")
    } else if (depth == 2 && stack[2] == "effects" && (name == "effect" || name == "effectProxy")) {
        effect = attr(tag, "name")
        uuid = tolower(attr(tag, "uuid"))
        type = tolower(attr(tag, "type"))
        if (effect !~ /^[[:alnum:]_.-]+$/ || !valid_uuid(uuid)) return
        if (effect != "noise_suppression" && type != noise_type &&
            !(factory == "hidl" && (effect == "ns" || uuid == aosp_noise))) return
        if (name == "effectProxy") {
            proxies[effect] = 1
        } else {
            names[++nc] = effect
            uuid_for[effect] = uuid
            library_for[effect] = attr(tag, "library")
        }
    } else if (depth == 2 && stack[2] == "preprocess" && name == "stream") {
        type = attr(tag, "type")
        if (want["preprocess", type] && seen_stream[type]++) fail()
    } else if (depth == 3 && stack[2] == "preprocess" && stack[3] == "stream" && name == "apply") {
        configured[stream[3], attr(tag, "effect")] = 1
    }
}
function select_stock(    i, j, effect, path, score, best) {
    for (i = 1; i <= nc; i++) {
        effect = names[i]
        path = libraries[library_for[effect]]
        if (path == "" || library_for[effect] == "clarifae") continue
        score = configured["voice_communication", effect] ? 2 : 1
        if (score > best) {
            chosen = effect
            best = score
        }
        for (j = 1; j <= ni; j++)
            if (configured[inputs[j], effect] && !stock_applied[inputs[j]]) stock_applied[inputs[j]] = effect
    }
    for (effect in proxies)
        for (j = 1; j <= ni; j++)
            if (configured[inputs[j], effect] && !stock_applied[inputs[j]]) stock_applied[inputs[j]] = effect
    if (chosen == "") {
        print "No recognized stock noise suppressor is declared" > "/dev/stderr"
        fail()
    }
}
function stock_edit(text) {
    return "<!-- Clarifae stock begin -->" text "<!-- Clarifae stock end -->"
}
function entries(section) {
    if (section == "libraries") {
        printf "\n        <library name=\"clarifae\" path=\"libclarifae.so\"/>\n    "
    } else {
        printf "\n        <effect name=\"clarifae_ns\" library=\"clarifae\" uuid=\"%s\"/>", uuid_in
        printf "\n        <effect name=\"clarifae_out\" library=\"clarifae\" uuid=\"%s\"/>\n    ", uuid_out
    }
}
function apply(effect,    text) {
    text = "<apply effect=\"" effect "\"/>"
    if (stock) text = stock_edit(text)
    printf "\n            %s\n        ", text
}
function missing_streams(section,    i, key, text) {
    if (section == "preprocess") {
        for (i = 1; i <= ni; ++i) {
            key = inputs[i]
            if (key == "" || used[section, key]) continue
            text = "<stream type=\"" key "\"><apply effect=\"" (stock ? chosen : "clarifae_ns") "\"/></stream>"
            printf "\n        %s", stock ? stock_edit(text) : text
        }
    } else {
        for (i = 1; i <= no; ++i) {
            key = outputs[i]
            if (key != "" && !used[section, key])
                printf "\n        <stream type=\"%s\"><apply effect=\"clarifae_out\"/></stream>", key
        }
    }
    printf "\n    "
}
function close_tag(name,    section, key) {
    if (name == "audio_effects_conf" && depth == 1) {
        if (!seen["libraries"] || !seen["effects"]) fail()
        roots++
        if (discovering) return
        if (!seen["preprocess"] && ni > 0) {
            printf "\n    <preprocess>"
            missing_streams("preprocess")
            printf "</preprocess>\n"
        }
        if (!seen["postprocess"] && no > 0) {
            printf "\n    <postprocess>"
            missing_streams("postprocess")
            printf "</postprocess>\n"
        }
    } else if (discovering) {
        return
    } else if (depth == 2) {
        if (!stock && (name == "libraries" || name == "effects")) entries(name)
        if (name == "preprocess" || (!stock && name == "postprocess")) missing_streams(name)
    } else if (depth == 3 && name == "stream") {
        section = stack[2]
        key = stream[depth]
        if (want[section, key] && !used[section, key]++ && !stock_applied[key])
            apply(stock ? chosen : (section == "preprocess" ? "clarifae_ns" : "clarifae_out"))
    }
}
function token(tag,    name, closing, empty, section, effect) {
    if (tag == "<!-- Clarifae stock begin -->") {
        if (stock_region) fail()
        stock_region = 1
        return
    }
    if (tag == "<!-- Clarifae stock end -->") {
        if (!stock_region) fail()
        stock_region = 0
        return
    }
    if (stock_region) return
    if (tag ~ /^<[?!]/) {
        emit(tag)
        return
    }
    closing = tag ~ /^<\//
    empty = tag ~ /\/[[:space:]]*>$/
    name = tag
    sub(/^<\/?/, "", name)
    sub(/[[:space:]\/>].*$/, "", name)
    if (closing) {
        if (!depth || name != stack[depth]) fail()
        close_tag(name)
        depth--
        emit(tag)
        return
    }
    if (discovering) stock_metadata(tag, name)
    section = stack[2]
    effect = attr(tag, "effect")
    # Strip our generated entries before reapplying, including on module upgrades.
    if ((depth == 2 && section == "libraries" && name == "library" && attr(tag, "name") == "clarifae") ||
        (depth == 2 && section == "effects" && name == "effect" && attr(tag, "library") == "clarifae") ||
        (depth == 3 && stack[3] == "stream" && name == "apply" &&
         (effect == "clarifae_ns" || effect == "clarifae_out"))) {
        if (!empty) fail()
        return
    }
    if (!depth && (name != "audio_effects_conf" || roots)) fail()
    if (depth == 1 && ++seen[name] > 1 &&
        (name == "libraries" || name == "effects" || name == "preprocess" || name == "postprocess")) fail()
    stack[++depth] = name
    if (depth == 3 && name == "stream") stream[depth] = attr(tag, "type")
    if (empty) {
        if (!discovering && ((depth == 2 && ((!stock && (name == "libraries" || name == "effects" ||
                                                        name == "postprocess")) || name == "preprocess")) ||
                            (depth == 3 && name == "stream" && want[section, stream[depth]]))) {
            sub(/\/[[:space:]]*>$/, ">", tag)
            emit(tag)
            close_tag(name)
            printf "</%s>", name
        } else {
            emit(tag)
        }
        depth--
    } else {
        emit(tag)
    }
}
BEGIN {
    stock = engine == "stock"
    noise_type = "58b4b260-8e06-11e0-aa8e-0002a5d5c51b"
    aosp_noise = "c06c8400-8e06-11e0-9cb6-0002a5d5c51b"
    ni = split(in_streams, inputs, " ")
    no = split(out_streams, outputs, " ")
    for (i = 1; i <= ni; ++i) want["preprocess", inputs[i]] = 1
    for (i = 1; i <= no; ++i) want["postprocess", outputs[i]] = 1
}
{ xml = xml $0 "\n" }
function walk(xml,    start, end) {
    while ((start = index(xml, "<"))) {
        if (!stock_region) emit(substr(xml, 1, start - 1))
        xml = substr(xml, start)
        if (xml ~ /^<!--/) {
            end = index(xml, "-->")
            if (!end) fail()
            end += 2
        } else if (xml ~ /^<\?/ && match(xml, /^<\?[^?]*(\?[^>][^?]*)*\?>/)) {
            end = RLENGTH
        } else if (match(xml, /^<[^<>'"]*("[^"]*"[^<>'"]*|'[^']*'[^<>'"]*)*>/)) {
            end = RLENGTH
        } else {
            fail()
        }
        token(substr(xml, 1, end))
        xml = substr(xml, end + 1)
    }
    if (invalid || stock_region || depth || roots != 1 || xml ~ /[^[:space:]]/) fail()
    emit(xml)
}
END {
    if (stock) {
        discovering = 1
        walk(xml)
        select_stock()
        for (section in seen) delete seen[section]
        roots = discovering = 0
    }
    walk(xml)
    if (stock && report != "") {
        print "Factory: " factory > report
        print "Stock effect: " chosen > report
        print "Stock UUID: " uuid_for[chosen] > report
        print "Stock library: " libraries[library_for[chosen]] > report
        for (i = 1; i <= ni; i++)
            print "Route " inputs[i] ": " (stock_applied[inputs[i]] ? stock_applied[inputs[i]] : chosen) > report
        close(report)
    }
}
