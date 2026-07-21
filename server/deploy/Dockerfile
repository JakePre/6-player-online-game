# Party Rush dedicated server image (M7-01).
#
# Build from the REPO ROOT (the compose file does this for you):
#   docker build -f server/deploy/Dockerfile -t party-rush-server .
#
# Stage 1 exports the "Linux Server" preset. Mirrors .github/workflows/ci.yml,
# which creates the output dir before exporting (Godot does not auto-create the
# export path and fails with "the given export path doesn't exist" otherwise).

FROM barichello/godot-ci:4.4.1 AS build
WORKDIR /src
COPY . .
RUN mkdir -p build/server \
	&& (godot --headless --import || true) \
	&& godot --headless --export-release "Linux Server" \
	&& ls -l build/server

# Stage 2: minimal runtime. The dedicated_server export runs with dummy
# display/audio drivers, so a slim base suffices.
FROM debian:bookworm-slim
RUN useradd --system --create-home --home-dir /app party && mkdir -p /app \
	&& chown party:party /app
WORKDIR /app
COPY --from=build --chown=party:party /src/build/server/ /app/
USER party

# ENet over UDP (SPEC $9).
EXPOSE 7777/udp

# The export carries the dedicated_server feature tag, so boot.gd starts the
# server without extra args; --port=<n> may be appended after `--`.
ENTRYPOINT ["./party-rush-server.x86_64", "--headless"]
