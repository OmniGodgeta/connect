# Connect

Hold the button, or just speak. No accounts.

Connect is an Android walkie-talkie for people already on this Tailscale network (`tail51f9d6.ts.net`). Opening the app joins Everyone. You can create another room, and friends on this network see it and can join it. The relay runs on this PC and is published with `tailscale serve`, so it is not on the public internet. A phone still needs the Tailscale app connected, or it cannot reach the room.

The repo is public so a link works for friends. The release APK is the download. Being on the tailnet is the access check.

![Connect](assets/brand/icon.png)

## Use it

1. Install [Tailscale](https://tailscale.com/download) and join this tailnet. The owner invites the phone.
2. Install the APK from the GitHub release.
3. Open Connect, type the name people should see, and join. You land in Everyone.
4. Tap Rooms to create a room or join one a friend created. One person talks at a time in each room.
5. The big number is how many people are in the room. Tap it to see who is there.
6. Choose Hold or Voice. Hold means press the big button. Voice means just speak, and tap the button to mute.
7. Noise cancelling is on. It uses the phone's noise suppressor, echo canceler, and automatic gain. Turn it off for the plain microphone.
8. Minimize Connect while a game is open. It listens for your voice, so you can talk without holding the button. Opening Connect again uses the Hold or Voice choice you saved. Swiping Connect away leaves the room. This PC has to be awake.

The game keeps its own sound while Connect is minimized. A loud game can still open the microphone, because noise cancelling then has no copy of the game audio to cancel.

Sound is 48 kHz mono, the same rate on every phone. Install 1.1.0 or newer on each phone. The 1.0.0 build used 16 kHz and will not sound right next to this one. Creating a room needs 1.2.0 or newer. A 1.1.0 phone stays in Everyone. Talking while a game is in front needs 1.3.0. A 1.2.0 phone still talks at 48 kHz, and it keeps listening in the background, but it does not switch to voice detection when you minimize it.

The name stays on the phone. There is no login.

## Develop

```bash
python3 -m venv server/.venv
server/.venv/bin/pip install -r server/requirements.txt
server/.venv/bin/python server/test_relay.py
server/.venv/bin/python server/relay.py   # 127.0.0.1:8792

cd /home/shadowswords/Work/connect
flutter analyze
flutter test
flutter run --dart-define=CONNECT_URL=ws://10.0.2.2:8792/ws
flutter build apk --release
```

The release build reads `android/key.properties` (gitignored). On this machine the upload key is `~/.config/connect/upload-keystore.jks`. Without that file the release build is signed with the debug key.

The shipped app calls `wss://retroverse.tail51f9d6.ts.net:8732/ws`.

## Relay on this PC

`server/connect-relay.service` is the user systemd unit. It listens on `127.0.0.1:8792` only.

```bash
systemctl --user enable --now connect-relay.service
tailscale serve --bg --https=8732 http://127.0.0.1:8792
curl -fsS http://127.0.0.1:8792/health
```

Port 443 on this tailnet is already the arcade. Connect uses **8732**. Do not reset `tailscale serve`; that would drop the other ports.

Outfit is under the SIL Open Font License. See `assets/fonts/OFL.txt`.
