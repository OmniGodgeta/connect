# Connect handoff

Updated 2026-10-04. Start here, then `AGENTS.md`.

## Shipped — 1.5.0

1.5.0+6 is the current release. Asset `connect-1.5.0.apk` on tag `v1.5.0`. 1.4.0+5 (`72b184b`, `connect-1.4.0.apk`) stays up. Friends need 1.5.0 for volume-key talk, the bubble, shared photos, the join/leave tone, and per-person volume. A 1.4.0 phone still talks at 48 kHz, shows painted pictures, listens for speech when minimized, and ignores the photo message.

The five features:

1. Volume keys are hold-to-talk while a game is in front. While Connect is minimized, it does not listen for speech. Holding volume up or volume down transmits, and releasing it stops. `VolumeTalkService` uses `flagRequestFilterKeyEvents` and `isAccessibilityTool`. It only consumes those two keys while the room is in the background. It does not read the screen. If the service is off, volume keys still change the game's volume and do not talk. On the emulator, `adb shell input keyevent` does not reach this service. A real key, or `uinput` with `KEY_VOLUMEDOWN`, does.
2. A small bubble over the game shows who is talking and a Talk button (hold). Native overlay (`SYSTEM_ALERT_WINDOW` / `TYPE_APPLICATION_OVERLAY`), not a second Flutter engine. The user grants display over other apps. Hide the bubble when the room service stops. The bubble and the volume keys use the same hold/release path. Opening Connect again restores the saved Hold or Voice choice. The mic stays closed until the user holds a key or the bubble.
3. A gallery photo, shown on every 1.5.0 phone in the room. The painted face stays the fallback. Text message `{"t":"photo","jpeg":"<base64>"}`. The relay stamps the sender id. JPEG cap is 24 KB. Image bytes never use the PCM channel.
4. A short local sound when someone else joins or leaves. The first roster after welcome is quiet, including after a room change. You do not chime for yourself.
5. A volume slider for each other person, saved on this phone (`connect.levels`). Gain is applied on playback. Your own voice meter is unchanged. Their picture follows the quieter audio. Default is full volume.

The room screen links to the two settings only when that grant is missing. `NoopAlerts` reports both granted so the 800x600 widget test does not show those buttons.

Standing rules: `cd` into `connect`. No Hermes, no model switch, no fine-tune. Do not print the keystore password. Do not commit `android/key.properties`, the keystore, `server/.venv`, `build/`, or APKs. Cert SHA-256 stays `39b45b725ff851d34a7cd5d5fb62ad31862fa70137d9b319c61d081f836f7a41`. Two-phone hearing is still an operator check. Emulator is `pixel_api35` with `-no-audio`. Confirm it is stopped with `pgrep qemu-system` (a shell line that contains `emulator` false-matches `pgrep -f`).

## Resume status

1.5.0 is released. The relay on this PC is already running the photo-aware `server/relay.py` (`connect-relay.service` was restarted, health `ok`). Do not run `tailscale serve reset`. The next operator step is two real phones, plus the volume-key accessibility service and display over other apps.

## What this is

Android walkie-talkie. Package `com.shadowswords.connect`, version 1.5.0+6. No accounts. The first open asks for a display name (1–24 characters) and saves it on the phone with a stable id. Later opens join the last room, or Everyone. Rooms can be created from the Rooms button. Talk is either hold-to-talk or voice detection. Minimizing the app does not listen for speech. Hold a volume key, or Talk on the bubble, to talk over a game. The member count opens the list. Each person has a picture, and the picture of whoever is talking moves with their voice. One speaker at a time in a room. Dark theme only. Audio is 48 kHz mono PCM16. Noise cancelling defaults on.

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
- 1.4.0: `flutter analyze` was clean and `flutter test` passed (21). The relay was not restarted.
- Same emulator, 1.4.0 debug build: Eric's picture was in the room, with a smaller copy under the count. Alex joined with a different picture. While Alex held the floor on a low tone, the large picture became Alex, the rings around it brightened, and the screen said "Alex is talking". The member list showed both pictures. Speaker playback was still not heard (`-no-audio`).
- 1.5.0: `flutter analyze` was clean and `flutter test` passed (28). `server/test_relay.py` passed. `connect-relay.service` was restarted onto this relay. Health returned `ok`. A second client sent a 773-byte JPEG. Eric's painted face stayed, and Alex showed as that photo. The member slider for Alex moved from 100% to 7%. With both grants on, the room did not show "Volume keys" or "Bubble over games". The hint under noise cancelling said to hold a volume key or the bubble in a game.
- Same emulator, backgrounded on the launcher: the bubble read "Hold to talk" with a Talk button. The notification was "Hold a volume key to talk in Everyone". Holding Talk changed the bubble to "You're talking", the relay granted Eric the floor, and PCM frames (3840 bytes) flowed until release.
- A virtual volume-down key (`uinput`, `KEY_VOLUMEDOWN`) while armed was received as key 25, did not change the music volume (the key was consumed), granted Eric the floor, and streamed PCM until release. `adb shell input keyevent` never reached `VolumeTalkService` on this emulator. Speaker playback was still not heard (`-no-audio`). The emulator was then stopped (`pgrep qemu-system` empty).
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
- While a game is in front, a 1.3.0 or 1.4.0 phone uses normal mode and leaves the speakerphone alone, so the game is not forced into a phone call. Noise cancelling stays on if the switch is on, but a loud game can still open the mic. 1.5.0 does not listen for speech while minimized.
- Android 14 and newer need the foreground service type `mediaPlayback|microphone`, and the microphone permission, or the mic stops when the activity is not in front. The first start stays playback-only until that permission is granted.
- The big number is the people in the room. Tapping it opens the list. 1.2.0 still talks at 48 kHz and can use named rooms. It does not switch to voice detection when minimized.

## Pictures (1.4.0)

- The picture is painted from the person's id. Changing their name does not change the face. Every 1.4.0 phone draws the same face for the same person. Nothing is uploaded, and the relay is unchanged.
- The room shows that picture large, with the other people as smaller pictures along the bottom. The member list shows them too.
- While someone is talking, their picture grows with the low part of the voice and pulls in a little on a brighter tone. Cyan rings around it move with the same sound. Your own picture does this while you hold the floor. Theirs does it from the audio you hear.
- A 1.3.0 phone still talks at 48 kHz and listens when minimized. It does not show the pictures.

## Over a game (1.5.0)

- Minimizing no longer listens for speech. Holding volume up or volume down transmits, and releasing it stops. The same hold works on the Talk control in the bubble. The bubble names whoever is talking. Opening Connect again restores the saved Hold or Voice choice, including a voice mute.
- Volume keys need Connect's accessibility service turned on. The service only takes those two keys while the room is behind another app. It does not read the screen. The bubble needs permission to display over other apps. The room screen links to both settings when they are off. Without them, you can still listen, and you talk with the button inside Connect.
- While you hold the floor from a volume key or the bubble, the mic stays in normal mode so the game keeps its own sound.

## Photos, sounds, and volume (1.5.0)

- Add a photo, or tap your picture, to pick one from the gallery. Connect crops it and sends a small JPEG. Other 1.5.0 phones show it. If you have not picked one, or a phone is still on 1.4.0, the painted face is used. Remove photo clears it for the room. Nothing is uploaded to a public host.
- The relay message is `{"t":"photo","id":"...","jpeg":"<base64>"}`. The phone sends the JPEG and the relay stamps the id. The cap is 24 KB. Binary frames stay PCM. Restart `connect-relay.service` after changing the relay. Do not run `tailscale serve reset`.
- Someone else joining or leaving plays a short tone on this phone. The people already there when you arrive, and a room change, do not each play it. You do not chime for yourself.
- The member list has a volume slider for each other person. It is saved on this phone (`connect.levels`). Their picture follows the quieter audio. Your own voice is unchanged.

## Not checked on a phone

No physical device was attached. A real two-phone test is still for the operator: Tailscale connected on each phone, this PC awake, 1.5.0 on each phone that should use volume keys, the bubble, shared photos, the join/leave tone, and per-person volume. On each phone, turn on Connect's volume-key accessibility service and allow display over other apps. A 1.4.0 phone still talks, shows painted pictures, and listens for speech when minimized. Hold to talk and voice detection, noise cancelling on and off, create a room and have the other phone join it, the other phone hears it, the picture moves while they speak, and swipe-away leaves the room. The emulator had no speaker, so hearing the other person is still unchecked.

## Operator steps

1. Invite any friend who is not already on tailnet `tail51f9d6.ts.net`.
2. Send https://github.com/OmniGodgeta/connect/releases/download/v1.5.0/connect-1.5.0.apk. Volume keys, the bubble, a shared photo, the join/leave sound, and per-person volume need this build. A 1.4.0 phone still talks, shows painted pictures, and listens for speech when minimized. A 1.0.0 phone plays 48 kHz audio at the wrong speed. A private repo link would 404 unless they are collaborators, which is why the repo is public. The relay stays tailnet-only. On the phone, also turn on Volume keys (accessibility) and allow the bubble over other apps.
3. On the phone: install the APK, connect Tailscale, open Connect, enter a name.
4. Keep this PC awake while people are in the room.

## Do not

- Bind the relay on `0.0.0.0`.
- Turn on Tailscale Funnel for this app.
- Run `tailscale serve reset`.
- Commit `android/key.properties`, the keystore, or `server/.venv`.
- Switch the Hermes model or fine-tune a local model to work on this app. Hermes does not build it.
