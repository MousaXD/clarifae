# Preserve OEM legacy blocks and merge Clarifae into the existing stream.
function fail() { invalid = 1; exit 1 }
function emit(text) { if (!skip) printf "%s", text }
function flush() { emit(held); held = name = "" }
function routing(section) {
    return section == "pre_processing" || section == "output_session_processing"
}
function effect_for(section) {
    return section == "pre_processing" ? "clarifae_ns" : "clarifae_out"
}
function missing(section,    key) {
    for (key in targets) {
        split(key, route, SUBSEP)
        if (route[1] == section && !routed[key])
            printf "\n  %s { %s {} }", route[2], effect_for(section)
    }
    printf "\n"
}
function token(text,    section, group, own, key) {
    if (text ~ /^[[:space:]#]/) {
        if (name != "") held = held text
        else emit(text)
    } else if (text == "{") {
        if (name == "") fail()
        section = stack[1]
        group = name
        own = (depth == 1 && section == "libraries" && group == "clarifae") ||
              (depth == 1 && section == "effects" && group ~ /^clarifae_(ns|out)$/) ||
              (depth == 2 && (routing(section) || section == "post_processing") &&
               group ~ /^clarifae_(ns|out)$/)
        stack[++depth] = group
        if (depth == 1 && ++seen[group] > 1 &&
            (group == "libraries" || group == "effects" || routing(group))) fail()
        if (own && !skip) skip = depth
        flush()
        emit(text)
    } else if (text == "}") {
        if (!depth) fail()
        flush()
        group = stack[depth]
        section = stack[1]
        key = section SUBSEP group
        if (skip) {
            if (skip == depth) skip = 0
        } else {
            if (depth == 2 && key in targets) {
                printf "\n    %s {}\n  ", effect_for(section)
                routed[key] = 1
            } else if (depth == 1 && group == "libraries") {
                printf "\n  clarifae {\n    path %s\n  }\n", lib_path
            } else if (depth == 1 && group == "effects") {
                printf "\n  clarifae_ns {\n    library clarifae\n    uuid %s\n  }\n", uuid_in
                printf "  clarifae_out {\n    library clarifae\n    uuid %s\n  }\n", uuid_out
            } else if (depth == 1 && routing(group)) {
                missing(group)
            }
            emit(text)
        }
        depth--
    } else {
        flush()
        name = held = text
    }
}
BEGIN {
    ni = split(in_streams, input, " ")
    no = split(out_streams, output, " ")
    for (i = 1; i <= ni; ++i) if (input[i] != "") targets["pre_processing", input[i]] = 1
    for (i = 1; i <= no; ++i) if (output[i] != "") targets["output_session_processing", output[i]] = 1
}
{
    line = $0
    while (length(line)) {
        if (!match(line, /^([[:space:]]+|#.*|[{}]|"([^"\\]|\\.)*"|[^[:space:]{}#"]+)/)) fail()
        token(substr(line, 1, RLENGTH))
        line = substr(line, RLENGTH + 1)
    }
    token("\n")
}
END {
    if (invalid || depth || !seen["libraries"] || !seen["effects"]) exit 1
    flush()
    if (!seen["pre_processing"] && ni > 0) {
        printf "\npre_processing {"
        missing("pre_processing")
        printf "}\n"
    }
    if (!seen["output_session_processing"] && no > 0) {
        printf "\noutput_session_processing {"
        missing("output_session_processing")
        printf "}\n"
    }
}
