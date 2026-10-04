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
- While Connect is open, talk is Hold or Voice. Minimizing does not listen for speech, so a loud game cannot open the mic. Holding a volume key, or Talk on the bubble, transmits until you let go. The saved Hold or Voice choice comes back when Connect is open again. Volume keys need the accessibility service `VolumeTalkService` (`flagRequestFilterKeyEvents` only, it does not read the screen). The bubble is a native overlay (`SYSTEM_ALERT_WINDOW`), not a second Flutter engine. Both are user grants. The foreground service type is `mediaPlayback|microphone`. The member count opens the list of people in the room.
- Each person has a painted picture from their id until they pick a gallery photo. A photo is JSON `{"t":"photo","jpeg":"<base64>"}`, at most 24 KB. The relay stamps the sender id. Image bytes never use the PCM channel. A 1.4.0 phone ignores that message. While someone talks, the picture grows with the bass and shrinks a little on a brighter tone. Rings around it follow the same voice. Their picture follows the volume you set for them.
- Typed chat is JSON too. The phone sends `{"t":"say","text":"..."}`. The relay stamps id and name, caps a line at 240 characters, keeps 40 lines per room, and sends `{"t":"chatlog","lines":[...]}` to someone who just joined. Drop the log when the room is empty. A 1.5.0 phone ignores `say` and `chatlog`.
- Playback must feed samples when they arrive after listening has already started. `SpeakerFeed` does that. `FlutterPcmSound.start()` only asks once.
- The in-app updater reads the public GitHub latest release and installs `connect-X.Y.Z.apk` through `PackageInstaller` plus `InstallStatusReceiver`. Do not use `PendingIntent.getActivity` for that result.
- A join or leave plays a short local tone. The first roster after welcome is quiet. Per-person volume is saved on the phone as `connect.levels` and applied on playback.
- Restart `connect-relay.service` after a relay change. Never `tailscale serve reset`.
- A hello with no room joins Everyone. A room name creates the room. Empty rooms disappear. The cap is 16 occupied rooms and 24 people in a room. The last room is saved on the phone as `connect.room`.
- This PC has to be awake or the room is down.
- Hermes (`gemma4-12b`) does not build this app. Do not switch that model for it.

## Check

```bash
server/.venv/bin/python server/test_relay.py
flutter analyze && flutter test
curl -fsS http://127.0.0.1:8792/health
```
