# Connect

One room. Hold the button to talk. No accounts.

Connect is an Android walkie-talkie for people already on this Tailscale network (`tail51f9d6.ts.net`). Opening the app joins the only room. The relay runs on this PC and is published with `tailscale serve`, so it is not on the public internet. A phone still needs the Tailscale app connected, or it cannot reach the room.

The repo is public so a link works for friends. The release APK is the download. Being on the tailnet is the access check.

![Connect](assets/brand/icon.png)

## Use it

1. Install [Tailscale](https://tailscale.com/download) and join this tailnet. The owner invites the phone.
2. Install the APK from the GitHub release.
3. Open Connect, type the name people should see, and join.
4. Hold the big button to talk. Let go to listen. One person talks at a time.
5. Leave the app in the background to keep hearing the room. Swiping it away leaves the room. This PC has to be awake.

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
