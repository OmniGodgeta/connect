#!/usr/bin/env python3
"""Push-to-talk relay with named rooms.

Listens on localhost. Tailscale serve publishes it to the tailnet.
There are no accounts. Anyone who can open the socket can join a room.

A hello with no room lands in Everyone, which is always listed. A hello
or a later join with a room name creates that room when it is new.
Empty rooms disappear. Each room has its own floor and roster.

Text frames are JSON. Binary frames are PCM signed-16 little-endian,
mono, at the sample rate the apps agreed on. The relay does not care
about the rate; it forwards bytes from whoever holds that room's floor.

A photo is a text frame, never a binary frame. The JPEG stays under
24 KB. Older apps ignore the message type and keep working.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import logging
import re
import time
import unicodedata
from dataclasses import dataclass
from typing import Any

from websockets.asyncio.server import ServerConnection, serve
from websockets.exceptions import ConnectionClosed
from websockets.http11 import Request, Response

log = logging.getLogger("connect.relay")

DEFAULT_ROOM = "Everyone"
MAX_PEOPLE = 24
MAX_ROOMS = 16
MAX_FRAME = 32_000
MAX_PHOTO = 24 * 1024
_ID = re.compile(r"^[A-Za-z0-9_-]{8,64}$")


def clean_name(raw: Any) -> str | None:
    if not isinstance(raw, str):
        return None
    name = unicodedata.normalize("NFC", " ".join(raw.split()))
    if not name or len(name) > 24:
        return None
    return name


def valid_id(raw: Any) -> bool:
    return isinstance(raw, str) and _ID.fullmatch(raw) is not None


def photo_bytes(raw: Any) -> bytes | None:
    """Return JPEG bytes, b"" to clear, or None when the message is ignored."""
    if raw == "":
        return b""
    if not isinstance(raw, str) or len(raw) > 40_000:
        return None
    try:
        data = base64.b64decode(raw, validate=True)
    except Exception:
        return None
    if len(data) < 4 or len(data) > MAX_PHOTO:
        return None
    if data[0] != 0xFF or data[1] != 0xD8:
        return None
    return data


@dataclass
class Client:
    id: str
    name: str
    ws: ServerConnection
    room: str = DEFAULT_ROOM
    wants_rooms: bool = False
    photo: bytes | None = None


class Room:
    def __init__(
        self,
        floor_audio_timeout: float = 8.0,
        watch_interval: float = 0.5,
        max_people: int = MAX_PEOPLE,
        max_rooms: int = MAX_ROOMS,
    ) -> None:
        self.floor_audio_timeout = floor_audio_timeout
        self.watch_interval = watch_interval
        self.max_people = max_people
        self.max_rooms = max_rooms
        self.clients: dict[str, Client] = {}
        self.speakers: dict[str, str] = {}
        self._deadlines: dict[str, float] = {}
        self._lock = asyncio.Lock()
        self._watch = True

    def stop(self) -> None:
        self._watch = False

    def _occupied(self, ignoring: str | None = None) -> set[str]:
        return {c.room for c in self.clients.values() if c.id != ignoring}

    def _can_open(self, room_name: str, ignoring: str | None = None) -> bool:
        occupied = self._occupied(ignoring)
        if room_name in occupied or room_name == DEFAULT_ROOM:
            return True
        return len(occupied) < self.max_rooms

    def _others_in(self, room_name: str, ident: str) -> int:
        return sum(1 for c in self.clients.values() if c.room == room_name and c.id != ident)

    def _release_locked(self, room_name: str, ident: str) -> bool:
        if self.speakers.get(room_name) != ident:
            return False
        self.speakers.pop(room_name, None)
        self._deadlines.pop(room_name, None)
        return True

    def _rows_locked(self) -> list[dict[str, Any]]:
        counts: dict[str, int] = {}
        for client in self.clients.values():
            counts[client.room] = counts.get(client.room, 0) + 1
        counts.setdefault(DEFAULT_ROOM, 0)
        names = [DEFAULT_ROOM] + sorted(name for name in counts if name != DEFAULT_ROOM)
        return [{"name": name, "people": counts[name]} for name in names]

    def _room_name(self, msg: dict[str, Any]) -> str | None:
        if "room" not in msg or msg.get("room") is None:
            return DEFAULT_ROOM
        return clean_name(msg.get("room"))

    async def hello(self, ws: ServerConnection, raw: str) -> Client | None:
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            await ws.close(1008, "bad hello")
            return None
        if not isinstance(msg, dict) or msg.get("t") != "hello":
            await ws.close(1008, "hello first")
            return None
        name = clean_name(msg.get("name"))
        ident = msg.get("id")
        if name is None or not valid_id(ident):
            await _send(ws, {"t": "error", "code": "name"})
            await ws.close(1008, "bad name")
            return None
        room_name = self._room_name(msg)
        if room_name is None:
            await _send(ws, {"t": "error", "code": "room"})
            await ws.close(1008, "bad room")
            return None

        old: Client | None = None
        client: Client | None = None
        cleared_room: str | None = None
        full = False
        blocked = False
        async with self._lock:
            if not self._can_open(room_name, ident):
                blocked = True
            elif self._others_in(room_name, ident) >= self.max_people:
                full = True
            else:
                old = self.clients.get(ident)
                if old is not None and self._release_locked(old.room, ident):
                    cleared_room = old.room
                if self.speakers.get(room_name) == ident:
                    self._release_locked(room_name, ident)
                    cleared_room = cleared_room or room_name
                client = Client(
                    ident,
                    name,
                    ws,
                    room_name,
                    photo=old.photo if old is not None else None,
                )
                self.clients[ident] = client
        if blocked:
            await _send(ws, {"t": "error", "code": "rooms"})
            await ws.close(1008, "rooms")
            return None
        if full:
            await _send(ws, {"t": "error", "code": "full"})
            await ws.close(1013, "full")
            return None
        if old is not None:
            try:
                await old.ws.close(4000, "replaced")
            except ConnectionClosed:
                pass
        assert client is not None
        await _send(ws, {"t": "welcome", "id": ident, "name": name, "room": room_name})
        await self._broadcast_roster(room_name)
        await self._send_room_photos(client)
        if client.photo:
            await self._broadcast_photo(room_name, client.id, client.photo)
        if old is not None and old.room != room_name:
            await self._broadcast_roster(old.room)
        if cleared_room is not None and old is not None:
            await self._broadcast_talk(cleared_room, old.id, old.name, False)
        await self._push_rooms()
        log.info("join id=%s name=%s room=%s people=%s", ident, name, room_name, len(self.clients))
        return client

    async def text(self, client: Client, raw: str) -> None:
        try:
            msg = json.loads(raw)
        except json.JSONDecodeError:
            return
        if not isinstance(msg, dict):
            return
        kind = msg.get("t")
        if kind == "ptt":
            down = msg.get("down")
            if isinstance(down, bool):
                await self.ptt(client, down)
        elif kind == "hello":
            await self.rename(client, msg.get("name"))
        elif kind == "join":
            await self.move(client, msg.get("room"))
        elif kind == "rooms":
            await self.subscribe_rooms(client, msg.get("watch") is not False)
        elif kind == "photo":
            await self.photo(client, msg.get("jpeg"))

    async def subscribe_rooms(self, client: Client, watch: bool) -> None:
        rows: list[dict[str, Any]] | None = None
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            client.wants_rooms = watch
            if watch:
                rows = self._rows_locked()
        if rows is not None:
            await _send(client.ws, {"t": "rooms", "rooms": rows})

    async def rename(self, client: Client, raw: Any) -> None:
        name = clean_name(raw)
        if name is None:
            await _send(client.ws, {"t": "error", "code": "name"})
            return
        room_name = DEFAULT_ROOM
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            client.name = name
            room_name = client.room
        await self._broadcast_roster(room_name)

    async def move(self, client: Client, raw: Any) -> None:
        room_name = clean_name(raw)
        if room_name is None:
            await _send(client.ws, {"t": "error", "code": "room"})
            return
        old_room: str | None = None
        was_speaker = False
        same = False
        full = False
        blocked = False
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            if client.room == room_name:
                same = True
            elif not self._can_open(room_name, client.id):
                blocked = True
            elif self._others_in(room_name, client.id) >= self.max_people:
                full = True
            else:
                old_room = client.room
                was_speaker = self._release_locked(old_room, client.id)
                client.room = room_name
        if same:
            await _send(
                client.ws,
                {"t": "welcome", "id": client.id, "name": client.name, "room": room_name},
            )
            return
        if blocked:
            await _send(client.ws, {"t": "error", "code": "rooms"})
            return
        if full:
            await _send(client.ws, {"t": "error", "code": "full"})
            return
        await _send(
            client.ws,
            {"t": "welcome", "id": client.id, "name": client.name, "room": room_name},
        )
        if was_speaker and old_room is not None:
            await self._broadcast_talk(old_room, client.id, client.name, False)
        if old_room is not None:
            await self._broadcast_roster(old_room)
        await self._broadcast_roster(room_name)
        await self._send_room_photos(client)
        if client.photo:
            await self._broadcast_photo(room_name, client.id, client.photo)
        await self._push_rooms()
        log.info("move id=%s room=%s", client.id, room_name)

    async def photo(self, client: Client, raw: Any) -> None:
        data = photo_bytes(raw)
        if data is None:
            return
        room_name = client.room
        blob: bytes | None
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            room_name = client.room
            client.photo = None if data == b"" else data
            blob = client.photo
        log.info("photo id=%s bytes=%s", client.id, 0 if blob is None else len(blob))
        await self._broadcast_photo(room_name, client.id, blob)

    async def ptt(self, client: Client, down: bool) -> None:
        granted = False
        released = False
        denied_by: str | None = None
        room_name = client.room
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            room_name = client.room
            holder_id = self.speakers.get(room_name)
            if down:
                if holder_id is None or holder_id == client.id:
                    self.speakers[room_name] = client.id
                    self._deadlines[room_name] = time.monotonic() + self.floor_audio_timeout
                    granted = True
                else:
                    holder = self.clients.get(holder_id)
                    if holder is not None and holder.room == room_name:
                        denied_by = holder.name
            elif holder_id == client.id:
                self._release_locked(room_name, client.id)
                released = True
        if down:
            payload: dict[str, Any] = {"t": "floor", "ok": granted}
            if not granted and denied_by:
                payload["by"] = denied_by
            await _send(client.ws, payload)
            if granted:
                log.info("floor id=%s name=%s room=%s", client.id, client.name, room_name)
                await self._broadcast_talk(room_name, client.id, client.name, True)
                await self._broadcast_roster(room_name)
            return
        if released:
            await self._broadcast_talk(room_name, client.id, client.name, False)
            await self._broadcast_roster(room_name)

    async def audio(self, client: Client, frame: bytes) -> None:
        if len(frame) < 2 or len(frame) > MAX_FRAME or len(frame) % 2:
            return
        room_name = client.room
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            room_name = client.room
            if self.speakers.get(room_name) != client.id:
                return
            self._deadlines[room_name] = time.monotonic() + self.floor_audio_timeout
            targets = [
                c for c in self.clients.values() if c.room == room_name and c is not client
            ]
        await self._send_many(targets, frame)

    async def leave_if_current(self, client: Client) -> None:
        should_end = False
        room_name = client.room
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            room_name = client.room
            del self.clients[client.id]
            should_end = self._release_locked(room_name, client.id)
        log.info("leave id=%s room=%s people=%s", client.id, room_name, len(self.clients))
        if should_end:
            await self._broadcast_talk(room_name, client.id, client.name, False)
        await self._broadcast_roster(room_name)
        await self._push_rooms()

    async def watch_floor(self) -> None:
        while self._watch:
            await asyncio.sleep(self.watch_interval)
            expired: list[Client] = []
            now = time.monotonic()
            async with self._lock:
                for room_name, deadline in list(self._deadlines.items()):
                    if now < deadline:
                        continue
                    ident = self.speakers.get(room_name)
                    client = self.clients.get(ident) if ident is not None else None
                    self.speakers.pop(room_name, None)
                    self._deadlines.pop(room_name, None)
                    if client is not None and client.room == room_name:
                        expired.append(client)
            for client in expired:
                log.info("floor timeout id=%s room=%s", client.id, client.room)
                await _send(client.ws, {"t": "floor", "ok": False, "reason": "timeout"})
                await self._broadcast_talk(client.room, client.id, client.name, False)
                await self._broadcast_roster(client.room)

    async def _send_room_photos(self, client: Client) -> None:
        async with self._lock:
            snaps = [
                (other.id, other.photo)
                for other in self.clients.values()
                if other.room == client.room and other.id != client.id and other.photo
            ]
        for ident, blob in snaps:
            await _send(client.ws, _photo_payload(ident, blob))

    async def _broadcast_photo(self, room_name: str, ident: str, blob: bytes | None) -> None:
        async with self._lock:
            targets = [c for c in self.clients.values() if c.room == room_name]
        await self._send_many(targets, _photo_payload(ident, blob))

    async def _broadcast_talk(self, room_name: str, ident: str, name: str, down: bool) -> None:
        async with self._lock:
            targets = [c for c in self.clients.values() if c.room == room_name]
        await self._send_many(targets, {"t": "talk", "id": ident, "name": name, "down": down})

    async def _broadcast_roster(self, room_name: str) -> None:
        async with self._lock:
            payload = {
                "t": "roster",
                "people": [
                    {"id": c.id, "name": c.name}
                    for c in self.clients.values()
                    if c.room == room_name
                ],
                "speaker": self.speakers.get(room_name),
            }
            targets = [c for c in self.clients.values() if c.room == room_name]
        await self._send_many(targets, payload)

    async def _push_rooms(self) -> None:
        async with self._lock:
            rows = self._rows_locked()
            targets = [c for c in self.clients.values() if c.wants_rooms]
        if targets:
            await self._send_many(targets, {"t": "rooms", "rooms": rows})

    async def _send_many(self, targets: list[Client], data: dict[str, Any] | bytes) -> None:
        failed: list[Client] = []

        async def one(client: Client) -> None:
            try:
                await _send(client.ws, data, timeout=2)
            except Exception:
                failed.append(client)

        await asyncio.gather(*(one(c) for c in targets))
        for client in failed:
            await self.leave_if_current(client)


def _photo_payload(ident: str, blob: bytes | None) -> dict[str, Any]:
    jpeg = "" if not blob else base64.b64encode(blob).decode("ascii")
    return {"t": "photo", "id": ident, "jpeg": jpeg}


async def _send(ws: ServerConnection, data: dict[str, Any] | bytes, timeout: float = 2) -> None:
    payload: str | bytes
    payload = data if isinstance(data, bytes) else json.dumps(data, separators=(",", ":"))
    await asyncio.wait_for(ws.send(payload), timeout)


def process_request(connection: ServerConnection, request: Request) -> Response | None:
    path = request.path.split("?", 1)[0]
    if path in ("/ws", "/ws/"):
        return None
    if path == "/health":
        return connection.respond(200, "ok\n")
    if path == "/":
        return connection.respond(200, "Connect relay is running.\n")
    return connection.respond(404, "not found\n")


async def handle(ws: ServerConnection, room: Room) -> None:
    client: Client | None = None
    try:
        raw = await asyncio.wait_for(ws.recv(), timeout=10)
        if not isinstance(raw, str):
            await ws.close(1008, "hello first")
            return
        client = await room.hello(ws, raw)
        if client is None:
            return
        async for message in ws:
            if isinstance(message, bytes):
                await room.audio(client, message)
            else:
                await room.text(client, message)
    except (ConnectionClosed, asyncio.TimeoutError):
        pass
    except Exception:
        log.exception("connection failed")
    finally:
        if client is not None:
            await room.leave_if_current(client)


async def serve_room(host: str, port: int, room: Room | None = None):
    room = room or Room()
    watcher = asyncio.create_task(room.watch_floor())

    def _handler(ws: ServerConnection) -> Any:
        return handle(ws, room)

    server = await serve(
        _handler,
        host,
        port,
        process_request=process_request,
        compression=None,
        max_size=65_536,
        max_queue=64,
        ping_interval=20,
        ping_timeout=20,
    )
    return server, watcher


def _http(status: int, body: bytes) -> bytes:
    reason = b"OK" if status == 200 else b"Not Found"
    return (
        f"HTTP/1.1 {status} {reason.decode()}\r\n".encode()
        + b"Content-Type: text/plain; charset=utf-8\r\n"
        + f"Content-Length: {len(body)}\r\n".encode()
        + b"Connection: close\r\n\r\n"
        + body
    )


async def _pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while True:
            chunk = await reader.read(65536)
            if not chunk:
                break
            writer.write(chunk)
            await writer.drain()
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def front_connection(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    backend_port: int,
) -> None:
    """Answer /health on this port and hand WebSocket upgrades to the relay."""
    try:
        data = b""
        while b"\r\n\r\n" not in data and len(data) < 8192:
            chunk = await asyncio.wait_for(reader.read(1024), timeout=5)
            if not chunk:
                return
            data += chunk
        head, _, _rest = data.partition(b"\r\n\r\n")
        first = head.split(b"\r\n", 1)[0].decode("latin1", "replace")
        parts = first.split(" ")
        path = parts[1].split("?", 1)[0] if len(parts) > 1 else "/"
        upgrade = b"upgrade: websocket" in head.lower()
        if upgrade:
            backend_r, backend_w = await asyncio.open_connection("127.0.0.1", backend_port)
            backend_w.write(data)
            await backend_w.drain()
            await asyncio.gather(_pipe(reader, backend_w), _pipe(backend_r, writer))
            return
        if path == "/health":
            writer.write(_http(200, b"ok\n"))
        elif path == "/":
            writer.write(_http(200, b"Connect relay is running.\n"))
        else:
            writer.write(_http(404, b"not found\n"))
        await writer.drain()
    except Exception:
        log.debug("front connection ended", exc_info=True)
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def listen(host: str, port: int, room: Room | None = None):
    """Public socket. WebSocket /ws is proxied to an internal relay."""
    room = room or Room()
    backend, watcher = await serve_room("127.0.0.1", 0, room)
    sockets = list(backend.sockets or [])
    backend_port = sockets[0].getsockname()[1]

    async def handler(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        await front_connection(reader, writer, backend_port)

    front = await asyncio.start_server(handler, host, port)
    return front, backend, watcher, room


def main() -> None:
    parser = argparse.ArgumentParser(description="Connect push-to-talk relay")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8792)
    args = parser.parse_args()
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    async def run() -> None:
        front, backend, watcher, room = await listen(args.host, args.port)
        bound = front.sockets[0].getsockname() if front.sockets else (args.host, args.port)
        log.info("listening on %s:%s", bound[0], bound[1])
        try:
            async with front:
                await front.serve_forever()
        finally:
            room.stop()
            watcher.cancel()
            backend.close()
            await backend.wait_closed()

    asyncio.run(run())


if __name__ == "__main__":
    main()
