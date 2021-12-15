FROM ghcr.io/dancojocaru2000/tdlib:so-v1.7.0-bullseye-slim AS tdlib

FROM dart:stable AS build
RUN apt-get update && apt-get install -y git

WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/telegirc_server.dart -o bin/server

FROM debian:bullseye-slim
# RUN apk update && apk upgrade && apk add --update libstdc++ zlib-dev openssl-dev sqlite-dev
RUN apt-get update && apt-get install -y zlib1g-dev libssl-dev libsqlite3-dev libc++-dev
COPY --from=tdlib /tdlib-so/libtdjson.so* /tdlib/lib/
ENV TDLIB_LIB_PATH=/tdlib/lib/libtdjson.so
# COPY --from=build /runtime /
COPY --from=build /app/bin/server /app/bin/

ENV IRC_UNSAFE_PORT=6667
EXPOSE ${IRC_UNSAFE_PORT}
ENV IRC_SAFE_PORT=6697
EXPOSE ${IRC_SAFE_PORT}
CMD ["/app/bin/server"]