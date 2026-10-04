# Connect

Android push-to-talk app. One shared room, no accounts, dark theme. Friends reach it through Tailscale, not the public internet.

## Layout

- `lib/` Flutter UI, floor control, microphone, playback.
- `server/relay.py` the room. Localhost only. One speaker at a time.
- `server/connect-relay.service` user unit for this PC.
- `android/key.properties` and `~/.config/connect/upload-keystore.jks` are the release key. Neither is committed.

## Rules

- Do not bind the relay on `0.0.0.0` and do not put it on Tailscale Funnel.
- `tailscale serve` for Connect is `--https=8732` to `127.0.0.1:8792`. Never `tailscale serve reset`.
- The app URL is `wss://retroverse.tail51f9d6.ts.net:8732/ws`.
- Audio is 16 kHz mono PCM16. The relay forwards bytes and does not decode them.
- This PC has to be awake or the room is down.
- Hermes (`gemma4-12b`) does not build this app. Do not switch that model for it.

## Check

```bash
server/.venv/bin/python server/test_relay.py
flutter analyze && flutter test
curl -fsS http://127.0.0.1:8792/health
```
