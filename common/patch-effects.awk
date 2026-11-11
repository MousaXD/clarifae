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
function entries(section) {
    if (section == "libraries") {
        printf "\n        <library name=\"clarifae\" path=\"libclarifae.so\"/>\n    "
    } else {
        printf "\n        <effect name=\"clarifae_ns\" library=\"clarifae\" uuid=\"%s\"/>", uuid_in
        printf "\n        <effect name=\"clarifae_out\" library=\"clarifae\" uuid=\"%s\"/>\n    ", uuid_out
    }
}
function apply(effect) {
    printf "\n            <apply effect=\"%s\"/>\n        ", effect
}
function missing_streams(section,    i, key) {
    if (section == "preprocess") {
        for (i = 1; i <= ni; ++i) {
            key = inputs[i]
            if (key != "" && !used[section, key])
                printf "\n        <stream type=\"%s\"><apply effect=\"clarifae_ns\"/></stream>", key
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
        roots++
    } else if (depth == 2) {
        if (name == "libraries" || name == "effects") entries(name)
        if (name == "preprocess" || name == "postprocess") missing_streams(name)
    } else if (depth == 3 && name == "stream") {
        section = stack[2]
        key = stream[depth]
        if (want[section, key] && !used[section, key]++)
            apply(section == "preprocess" ? "clarifae_ns" : "clarifae_out")
    }
}
function token(tag,    name, closing, empty, section, effect) {
    if (tag ~ /^<[?!]/) {
        printf "%s", tag
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
        printf "%s", tag
        return
    }
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
        if ((depth == 2 && (name == "libraries" || name == "effects" ||
                           name == "preprocess" || name == "postprocess")) ||
            (depth == 3 && name == "stream" && want[section, stream[depth]])) {
            sub(/\/[[:space:]]*>$/, ">", tag)
            printf "%s", tag
            close_tag(name)
            printf "</%s>", name
        } else {
            printf "%s", tag
        }
        depth--
    } else {
        printf "%s", tag
    }
}
BEGIN {
    ni = split(in_streams, inputs, " ")
    no = split(out_streams, outputs, " ")
    for (i = 1; i <= ni; ++i) want["preprocess", inputs[i]] = 1
    for (i = 1; i <= no; ++i) want["postprocess", outputs[i]] = 1
}
{ xml = xml $0 "\n" }
END {
    while ((start = index(xml, "<"))) {
        printf "%s", substr(xml, 1, start - 1)
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
    if (invalid || depth || roots != 1 || xml ~ /[^[:space:]]/) exit 1
    printf "%s", xml
}
