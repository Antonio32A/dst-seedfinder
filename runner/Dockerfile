# syntax=docker/dockerfile:1
ARG ALPINE=alpine:3.22

FROM ${ALPINE} AS build
RUN apk add --no-cache clang gcc musl-dev linux-headers
WORKDIR /src
COPY --from=csrc seedfinder.c .
RUN clang -std=c11 -O3 -mllvm -inline-threshold=3000 -march=x86-64 -mtune=generic \
        -static -Wl,-z,stack-size=8388608 -s seedfinder.c -lpthread -lm -o seedfinder \
    && ./seedfinder --help >/dev/null

FROM ${ALPINE}
RUN apk add --no-cache ca-certificates-bundle ssl_client
COPY --from=build /src/seedfinder /usr/local/bin/seedfinder
COPY --chmod=755 run.sh /runner/run.sh
ENTRYPOINT ["/runner/run.sh"]
