#!/usr/bin/env python3
"""One-room push-to-talk relay.

Listens on localhost. Tailscale serve publishes it to the tailnet.
There are no accounts. Anyone who can open the socket is in the room.

Text frames are JSON. Binary frames are PCM signed-16 little-endian,
mono, at the sample rate the apps agreed on. The relay does not care
about the rate; it forwards bytes from whoever holds the floor.
"""

from __future__ import annotations

import argparse
import asyncio
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

MAX_PEOPLE = 24
MAX_FRAME = 32_000
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


@dataclass
class Client:
    id: str
    name: str
    ws: ServerConnection


class Room:
    def __init__(self, floor_audio_timeout: float = 8.0, watch_interval: float = 0.5) -> None:
        self.floor_audio_timeout = floor_audio_timeout
        self.watch_interval = watch_interval
        self.clients: dict[str, Client] = {}
        self.speaker_id: str | None = None
        self._deadline: float | None = None
        self._lock = asyncio.Lock()
        self._watch = True

    def stop(self) -> None:
        self._watch = False

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

        old: Client | None = None
        client: Client | None = None
        cleared = False
        full = False
        async with self._lock:
            if ident not in self.clients and len(self.clients) >= MAX_PEOPLE:
                full = True
            else:
                old = self.clients.get(ident)
                client = Client(ident, name, ws)
                self.clients[ident] = client
                if self.speaker_id == ident:
                    self.speaker_id = None
                    self._deadline = None
                    cleared = True
        if full:
            await _send(ws, {"t": "error", "code": "full"})
            await ws.close(1013, "full")
            return None
        if old is not None:
            try:
                await old.ws.close(4000, "replaced")
            except ConnectionClosed:
                pass
        if cleared and old is not None:
            await self._broadcast_talk(old.id, old.name, False)
        assert client is not None
        await _send(ws, {"t": "welcome", "id": ident, "name": name})
        await self._broadcast_roster()
        log.info("join id=%s name=%s people=%s", ident, name, len(self.clients))
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

    async def rename(self, client: Client, raw: Any) -> None:
        name = clean_name(raw)
        if name is None:
            await _send(client.ws, {"t": "error", "code": "name"})
            return
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            client.name = name
        await self._broadcast_roster()

    async def ptt(self, client: Client, down: bool) -> None:
        granted = False
        released = False
        denied_by: str | None = None
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            if down:
                if self.speaker_id is None or self.speaker_id == client.id:
                    self.speaker_id = client.id
                    self._deadline = time.monotonic() + self.floor_audio_timeout
                    granted = True
                else:
                    holder = self.clients.get(self.speaker_id)
                    denied_by = holder.name if holder is not None else None
            elif self.speaker_id == client.id:
                self.speaker_id = None
                self._deadline = None
                released = True
        if down:
            payload: dict[str, Any] = {"t": "floor", "ok": granted}
            if not granted and denied_by:
                payload["by"] = denied_by
            await _send(client.ws, payload)
            if granted:
                log.info("floor id=%s name=%s", client.id, client.name)
                await self._broadcast_talk(client.id, client.name, True)
                await self._broadcast_roster()
            return
        if released:
            await self._broadcast_talk(client.id, client.name, False)
            await self._broadcast_roster()

    async def audio(self, client: Client, frame: bytes) -> None:
        if len(frame) < 2 or len(frame) > MAX_FRAME or len(frame) % 2:
            return
        async with self._lock:
            if self.speaker_id != client.id or self.clients.get(client.id) is not client:
                return
            self._deadline = time.monotonic() + self.floor_audio_timeout
            targets = [c for c in self.clients.values() if c is not client]
        await self._send_many(targets, frame)

    async def leave_if_current(self, client: Client) -> None:
        should_end = False
        async with self._lock:
            if self.clients.get(client.id) is not client:
                return
            del self.clients[client.id]
            if self.speaker_id == client.id:
                self.speaker_id = None
                self._deadline = None
                should_end = True
        log.info("leave id=%s people=%s", client.id, len(self.clients))
        if should_end:
            await self._broadcast_talk(client.id, client.name, False)
        await self._broadcast_roster()

    async def watch_floor(self) -> None:
        while self._watch:
            await asyncio.sleep(self.watch_interval)
            expired: Client | None = None
            async with self._lock:
                if (
                    self.speaker_id is not None
                    and self._deadline is not None
                    and time.monotonic() >= self._deadline
                ):
                    expired = self.clients.get(self.speaker_id)
                    self.speaker_id = None
                    self._deadline = None
            if expired is None:
                continue
            log.info("floor timeout id=%s", expired.id)
            await _send(expired.ws, {"t": "floor", "ok": False, "reason": "timeout"})
            await self._broadcast_talk(expired.id, expired.name, False)
            await self._broadcast_roster()

    async def _broadcast_talk(self, ident: str, name: str, down: bool) -> None:
        async with self._lock:
            targets = list(self.clients.values())
        await self._send_many(targets, {"t": "talk", "id": ident, "name": name, "down": down})

    async def _broadcast_roster(self) -> None:
        async with self._lock:
            payload = {
                "t": "roster",
                "people": [{"id": c.id, "name": c.name} for c in self.clients.values()],
                "speaker": self.speaker_id,
            }
            targets = list(self.clients.values())
        await self._send_many(targets, payload)

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
