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
    "COPY --from=golang:1.13-alpine /usr/local/go/ /usr/local/go/" \
    'ENV PATH="/usr/local/go/bin:${PATH}"' \
    "RUN set -uex; \\" \
    "    apk add --no-cache bash make" \
    "ENV BUILD_BY=$(hostname):$workdir" \
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
        -w "/workspace/$project" \
        "local/$project" \
        ./do in_container "$@"
    ;;
esac