# Connect handoff

Updated 2026-10-04. Start here, then `AGENTS.md`.

## What this is

Android walkie-talkie. Package `com.shadowswords.connect`, version 1.1.0+2. One shared room, no accounts. The first open asks for a display name (1–24 characters) and saves it on the phone with a stable id. Later opens join that room. Talk is either hold-to-talk or voice detection. One speaker at a time. Dark theme only. Audio is 48 kHz mono PCM16. Noise cancelling defaults on.

The relay is on this PC, localhost only. Phones reach it through Tailscale. It is not on the public internet and not on Funnel.

## What is running

- User unit `connect-relay.service` (from `server/connect-relay.service`). `Linger=yes`, so it stays up after logout. It still dies if this PC sleeps.
- Relay: `127.0.0.1:8792`. Health is `GET /health` → `ok`.
- `tailscale serve --bg --https=8732 http://127.0.0.1:8792`
- App URL: `wss://retroverse.tail51f9d6.ts.net:8732/ws`
- Port 443 on this tailnet is the arcade. Do not run `tailscale serve reset`.

## Checked on 2026-10-04

- `server/.venv/bin/python server/test_relay.py` passed.
- `flutter test` passed (7) on 2026-10-04 after the Android fixes.
- A two-client WSS check through `https://retroverse.tail51f9d6.ts.net:8732/ws` granted the floor and delivered PCM to the other peer.
- Emulator `pixel_api35` (`emulator-5554`), debug build with `CONNECT_URL=ws://10.0.2.2:8792/ws`: the name page rendered dark with the icon; a blank name showed "Use 1 to 24 characters."; joining as Eric reached the live room; a second client named Alex appeared on the roster; while Alex held the floor the screen said "Alex is talking"; Leave dropped Eric from the relay roster. The emulator was started with `-no-audio`, so speaker playback was not heard.
- Same emulator, 1.1.0 debug build: the room showed Hold and Voice, noise cancelling on, and "Hold to talk". Switching to Voice changed the line to "Listening for your voice" and the status bar showed the microphone open. Speaker playback was still not heard (`-no-audio`).
- `flutter build apk --release` produced `build/app/outputs/flutter-apk/app-release.apk` (about 49 MB). `apksigner` certificate SHA-256 matches `~/.config/connect/upload-keystore.jks` alias `connect` (`CN=Connect, OU=ShadowSwords, O=ShadowSwords, L=Toronto, ST=Ontario, C=CA`). The password is only in gitignored `android/key.properties`.
- `flutter_pcm_sound` 3.3.3 hardcodes compileSdk 33. `android/build.gradle.kts` raises library modules to 36 with `finalizeDsl`. Do not set compileSdk in `afterEvaluate`; AGP 9 rejects that.

## Audio (1.1.0)

- 48 kHz, 16-bit, mono. Frames are 40 ms so they stay under the relay's 32 KB cap. Playback uses the media stream, not the narrow voice-call stream.
- Noise cancelling on: `VOICE_COMMUNICATION`, noise suppressor, echo canceler, automatic gain, and communication mode so the speaker is less likely to trip the mic. Off: the plain mic, effects off.
- Voice mode keeps the mic open, asks for the floor after about 80 ms of speech, and holds it through a 600 ms pause. The first 220 ms is sent once the floor is granted so the start of a word is not cut off. Tap the button to mute. While someone else has the floor, the local mic stays closed.
- The choice and the noise-cancelling switch are saved on the phone (`connect.talk`, `connect.noise`).

## Not checked on a phone

No physical device was attached. A real two-phone test is still for the operator: Tailscale connected on each phone, this PC awake, every phone on 1.1.0, hold to talk and voice detection, noise cancelling on and off, the other phone hears it, screen-off listening, swipe-away leaves the room.

## Operator steps

1. Invite any friend who is not already on tailnet `tail51f9d6.ts.net`.
2. Send the public GitHub release link for the 1.1.0 APK. Every phone has to be on this build. A 1.0.0 phone plays 48 kHz audio at the wrong speed. A private repo link would 404 unless they are collaborators, which is why the repo is public. The relay stays tailnet-only.
3. On the phone: install the APK, connect Tailscale, open Connect, enter a name.
4. Keep this PC awake while people are in the room.

## Do not

- Bind the relay on `0.0.0.0`.
- Turn on Tailscale Funnel for this app.
- Run `tailscale serve reset`.
- Commit `android/key.properties`, the keystore, or `server/.venv`.
- Switch the Hermes model or fine-tune a local model to work on this app. Hermes does not build it.
