# Connect handoff

Updated 2026-10-04. Start here, then `AGENTS.md`.

## What this is

Android walkie-talkie. Package `com.shadowswords.connect`, version 1.3.0+4. No accounts. The first open asks for a display name (1–24 characters) and saves it on the phone with a stable id. Later opens join the last room, or Everyone. Rooms can be created from the Rooms button. Talk is either hold-to-talk or voice detection. Minimizing the app listens for speech so people can talk over a game. The member count opens the list. One speaker at a time in a room. Dark theme only. Audio is 48 kHz mono PCM16. Noise cancelling defaults on.

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
- 1.2.0: `server/test_relay.py` passed, including separate rooms, the room list, and the caps. `flutter analyze` was clean and `flutter test` passed (15). The user unit was restarted onto this relay. A live client created Cabin, saw it on the list, and joined Everyone.
- Same emulator, 1.2.0 debug build: the room opened as Eric in Everyone. Rooms showed Everyone with 1 person. Creating Cabin joined it. The list then showed Everyone empty and Cabin with 1 person. Tapping Everyone rejoined it. Speaker playback was still not heard (`-no-audio`).
- 1.3.0: `flutter analyze` was clean and `flutter test` passed (17). The relay was not restarted.
- Same emulator, 1.3.0 debug build: Everyone showed 2 members after a second person joined, and the names were not on the main screen. Tapping the number opened a Members list with Eric and Alex. Back closed the list and stayed in the room. Hold was selected, Home changed the notification to "Speak to talk in Everyone", and opening the app again showed "Hold to talk". The foreground service type was media playback and microphone. Speaker playback was still not heard (`-no-audio`).
- `flutter build apk --release` produced `build/app/outputs/flutter-apk/app-release.apk` (about 49 MB). `apksigner` certificate SHA-256 matches `~/.config/connect/upload-keystore.jks` alias `connect` (`CN=Connect, OU=ShadowSwords, O=ShadowSwords, L=Toronto, ST=Ontario, C=CA`). The password is only in gitignored `android/key.properties`.
- `flutter_pcm_sound` 3.3.3 hardcodes compileSdk 33. `android/build.gradle.kts` raises library modules to 36 with `finalizeDsl`. Do not set compileSdk in `afterEvaluate`; AGP 9 rejects that.

## Audio (1.1.0)

- 48 kHz, 16-bit, mono. Frames are 40 ms so they stay under the relay's 32 KB cap. Playback uses the media stream, not the narrow voice-call stream.
- Noise cancelling on: `VOICE_COMMUNICATION`, noise suppressor, echo canceler, automatic gain, and communication mode so the speaker is less likely to trip the mic. Off: the plain mic, effects off.
- Voice mode keeps the mic open, asks for the floor after about 80 ms of speech, and holds it through a 600 ms pause. The first 220 ms is sent once the floor is granted so the start of a word is not cut off. Tap the button to mute. While someone else has the floor, the local mic stays closed.
- The choice and the noise-cancelling switch are saved on the phone (`connect.talk`, `connect.noise`).

## Rooms (1.2.0)

- Everyone is always listed. A hello that omits `room` joins it, so a 1.1.0 phone still lands there and can talk with a 1.2.0 phone in that room.
- Rooms creates a room from a 1–24 character name, or joins it if someone is already there. The relay tells every phone that is looking at the list. An empty room disappears.
- Each room has its own floor, roster, and audio. At most 16 rooms have people in them, and 24 people in one room.
- The phone saves the last room in `connect.room` and rejoins it on the next open.

## Background voice and members (1.3.0)

- Home, or switching to a game, turns on voice detection. The saved Hold or Voice choice comes back when Connect is open again. A mute in Voice mode is lifted while minimized and put back on return. The notification shade does not change the mode.
- While a game is in front, the mic uses normal mode and leaves the speakerphone alone, so the game is not forced into a phone call. Noise cancelling stays on if the switch is on, but a loud game can still open the mic.
- Android 14 and newer need the foreground service type `mediaPlayback|microphone`, and the microphone permission, or the mic stops when the activity is not in front. The first start stays playback-only until that permission is granted.
- The big number is the people in the room. Tapping it opens the list. 1.2.0 still talks at 48 kHz and can use named rooms. It does not switch to voice detection when minimized.

## Not checked on a phone

No physical device was attached. A real two-phone test is still for the operator: Tailscale connected on each phone, this PC awake, 1.3.0 on each phone that should talk over a game (1.2.0 still talks at 48 kHz and can create rooms, 1.1.0 can still talk inside Everyone), hold to talk and voice detection, noise cancelling on and off, create a room and have the other phone join it, the other phone hears it, minimize onto a game and speak, swipe-away leaves the room.

## Operator steps

1. Invite any friend who is not already on tailnet `tail51f9d6.ts.net`.
2. Send the public GitHub release link for the 1.3.0 APK. Voice while a game is in front needs this build. A 1.2.0 phone still talks at 48 kHz and can create rooms, but it does not switch to voice detection when minimized. A 1.0.0 phone plays 48 kHz audio at the wrong speed. A 1.1.0 phone can still talk in Everyone. A private repo link would 404 unless they are collaborators, which is why the repo is public. The relay stays tailnet-only.
3. On the phone: install the APK, connect Tailscale, open Connect, enter a name.
4. Keep this PC awake while people are in the room.

## Do not

- Bind the relay on `0.0.0.0`.
- Turn on Tailscale Funnel for this app.
- Run `tailscale serve reset`.
- Commit `android/key.properties`, the keystore, or `server/.venv`.
- Switch the Hermes model or fine-tune a local model to work on this app. Hermes does not build it.
