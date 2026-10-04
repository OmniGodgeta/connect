# Connect

Android push-to-talk app. No accounts, dark theme. Everyone is the shared room. People can create other rooms. Friends reach it through Tailscale, not the public internet.

## Layout

- `lib/` Flutter UI, floor control, microphone, playback.
- `server/relay.py` the rooms. Localhost only. One speaker at a time in each room.
- `server/connect-relay.service` user unit for this PC.
- `android/key.properties` and `~/.config/connect/upload-keystore.jks` are the release key. Neither is committed.

## Rules

- Do not bind the relay on `0.0.0.0` and do not put it on Tailscale Funnel.
- `tailscale serve` for Connect is `--https=8732` to `127.0.0.1:8792`. Never `tailscale serve reset`.
- The app URL is `wss://retroverse.tail51f9d6.ts.net:8732/ws`.
- Audio is 48 kHz mono PCM16. The relay forwards bytes and does not decode them. Noise cancelling is the Android voice-communication path (noise suppressor, echo canceler, auto gain). Off uses the plain mic. Talk mode is hold or voice, saved on the phone.
- Minimizing the app listens for speech and does not write that over the saved Hold or Voice choice. While a game is in front, the mic stays in normal mode so the game keeps its audio path. The foreground service type is `mediaPlayback|microphone`. The member count opens the list of people in the room.
- A hello with no room joins Everyone. A room name creates the room. Empty rooms disappear. The cap is 16 occupied rooms and 24 people in a room. The last room is saved on the phone as `connect.room`.
- This PC has to be awake or the room is down.
- Hermes (`gemma4-12b`) does not build this app. Do not switch that model for it.

## Check

```bash
server/.venv/bin/python server/test_relay.py
flutter analyze && flutter test
curl -fsS http://127.0.0.1:8792/health
```
