#!/bin/bash -e

cd "$(dirname "$BASH_SOURCE")"
workdir="${WORKDIR:-$(pwd)}"
project="$(basename "$workdir")"

run() { echo -e "\x1b[33m>> $*\x1b[0m" >&2; "$@"; }

[ -r .env ] && { set -a; . .env; set +a; }

in_container() {

    # login to docker registry
    [ -n "$DOCKER_REPO_AUTH" ] && for it in $DOCKER_REPO_AUTH; do
        registry="${it#*@}"
        if [ "$registry" == "$REGISTRY" ]; then
            auth="${it%%@*}"
            run docker login --username "${auth%%:*}" --password-stdin "$registry" <<< "${auth#*:}"
        fi
    done

    case "$1" in
    build)
        run make build
        ;;
    *)
        "$@"
        ;;
    esac
}

case "$1" in
in_container)
    shift
    in_container "$@"
    ;;
workerimage)
    printf "%s\n" \
    "FROM docker:20-git" \
    "ARG GOSU_VERSION=1.16" \
    "COPY --from=golang:1.13-alpine /usr/local/go/ /usr/local/go/" \
    "ENV PATH=\"/usr/local/go/bin:\${PATH}\"" \
    "RUN set -uex; \\" \
    "    apk add --no-cache bash make ca-certificates dpkg; \\" \
    "    dpkgArch=\"\$(dpkg --print-architecture | awk -F- '{ print \$NF }')\"; \\" \
    "    wget -qO /usr/local/bin/gosu \"https://github.com/tianon/gosu/releases/download/\$GOSU_VERSION/gosu-\$dpkgArch\"; \\" \
    "    chmod +x /usr/local/bin/gosu; \\" \
    "    printf '%s\n' \\" \
    "       '#!/bin/bash -e' \\" \
    "       'if [ \"\$(id -u)\" -eq 0 ] && [ -n \"\$USER\" ]; then' \\" \
    "       '  groups=\"\${USER#*:}\"' \\" \
    "       '  for group in \${groups//,/ }; do' \\" \
    "       '    gid=\"\${group#*:}\"' \\" \
    "       '    if [ \"\$gid\" == \"\$group\" ]' \\" \
    "       '    then gn=\"user\"' \\" \
    "       '    else gn=\"\${group%%:*}\"' \\" \
    "       '    fi' \\" \
    "       '    group=\"\$(getent group \"\$gid\" | cut -d: -f1)\"' \\" \
    "       '    [ -n \"\$group\" ] || { addgroup -g \"\$gid\" \"\$gn\"; group=\"\$gn\"; }' \\" \
    "       '    if id user &>/dev/null' \\" \
    "       '    then addgroup user \"\$group\"' \\" \
    "       '    else adduser -u \"\${USER%%:*}\" -D user -G \"\$group\"' \\" \
    "       '    fi' \\" \
    "       '  done' \\" \
    "       '  id user &>/dev/null || adduser -u \"\${USER%%:*}\" -D user' \\" \
    "       '  gosu user test -w /var/run/docker.sock || chown \$(id -u user):\$(id -g user) /var/run/docker.sock' \\" \
    "       '  exec gosu user entrypoint \"\$@\"' \\" \
    "       'fi' \\" \
    "       'exec \"\$@\"' >/usr/local/bin/entrypoint; \\" \
    "    chmod +x /usr/local/bin/entrypoint; \\" \
    "    true" \
    "ENV BUILD_BY=$(hostname):$workdir" \
    "ENTRYPOINT [\"entrypoint\"]" \
    | run docker build --tag "local/$project" -
    ;;
build)
    "$BASH_SOURCE" workerimage
    shift
    [ $# -eq 0 ] && set -- make build
    run docker run -i$([ -t 0 ] && echo -n t) --rm \
        -v "/var/run/docker.sock:/var/run/docker.sock" \
        -v "$PWD:/workspace/$project" \
        -e WORKDIR="$workdir" \
        -e REGISTRY="${REGISTRY:-local}" \
        -e DOCKER_REPO_AUTH \
        -e USER="$(id -u):$(id -g),docker:$(stat -c %g /var/run/docker.sock 2>/dev/null || stat -f %g /var/run/docker.sock)" \
        -w "/workspace/$project" \
        "local/$project" \
        ./do in_container "$@"
    ;;
esac