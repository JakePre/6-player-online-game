# Deploying the Party Rush dedicated server

One server process hosts many rooms (SPEC §9); a 1-vCPU VPS is the design target (SPEC §13). The server speaks ENet over **UDP port 7777**.

## Quick start (any VPS with Docker)

```sh
git clone https://github.com/JakePre/6-player-online-game.git
cd 6-player-online-game/server/deploy
docker compose up -d --build
docker compose logs -f   # wait for: SERVER READY port=7777 protocol=N
```

Open the firewall for UDP:

```sh
sudo ufw allow 7777/udp        # Debian/Ubuntu with ufw
```

Point clients at the VPS: in-game **Settings → Network → Server address** (or the main menu's Advanced fold-out for a one-off session). Self-hosting is the supported override path per SPEC §9 — there is no server browser.

## Changing the port

The container always listens on 7777 internally; remap on the host side in `docker-compose.yml`:

```yaml
    ports:
      - "9999:7777/udp"
```

(Equivalently, append `-- --port=<n>` to the container command and match the mapping — the in-process flag exists, but host-side remapping is simpler.)

## Version handshake

Clients send `NetConfig.PROTOCOL_VERSION` with every create/join/rejoin request; the server rejects mismatches with `VERSION_MISMATCH` before any room state is touched (`src/server/room_manager.gd`), and the client shows "Your game version does not match the server." The running protocol number is printed in the startup line:

```
SERVER READY port=7777 protocol=2
```

**Operational rule:** rebuild the image from the same commit you ship clients from. After pulling a new version, `docker compose up -d --build` — connected players are dropped (rooms expire after 5 minutes empty), so upgrade between play sessions.

## Without Docker (bare VPS + systemd)

1. Export the `Linux Server` preset from the Godot editor (or grab the `server-linux` CI artifact from a green main build).
2. Copy `party-rush-server.x86_64` + `party-rush-server.pck` to `/opt/party-rush/` on the VPS.
3. Install a unit file:

```ini
# /etc/systemd/system/party-rush.service
[Unit]
Description=Party Rush dedicated server
After=network.target

[Service]
User=party
WorkingDirectory=/opt/party-rush
ExecStart=/opt/party-rush/party-rush-server.x86_64 --headless
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```sh
sudo useradd --system party
sudo systemctl enable --now party-rush
journalctl -u party-rush -f
```

## Monitoring

The server logs a heartbeat every 60 s (`[server] heartbeat rooms=N peers=M`) plus per-peer connect/disconnect and room-expiry lines — enough for `docker compose logs` / `journalctl` eyeballing until real telemetry is scheduled (post-v1).
