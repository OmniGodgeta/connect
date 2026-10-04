#!/usr/bin/env python3
"""Floor control, roster, and audio routing for the Connect relay."""

from __future__ import annotations

import asyncio
import json

from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed

from relay import Room, listen, serve_room


class Peer:
    def __init__(self, ws) -> None:
        self.ws = ws
        self.q: asyncio.Queue = asyncio.Queue()
        self.task = asyncio.create_task(self._read())

    async def _read(self) -> None:
        try:
            async for msg in self.ws:
                await self.q.put(msg)
        except ConnectionClosed:
            pass
        finally:
            await self.q.put(None)

    async def expect(self, kind: str, timeout: float = 2):
        msg = await self.next_json(timeout)
        assert msg["t"] == kind, msg
        return msg

    async def next_json(self, timeout: float = 2):
        msg = await asyncio.wait_for(self.q.get(), timeout)
        assert isinstance(msg, str), msg
        return json.loads(msg)

    async def next_bytes(self, timeout: float = 2) -> bytes:
        msg = await asyncio.wait_for(self.q.get(), timeout)
        assert isinstance(msg, bytes), msg
        return msg

    async def close(self) -> None:
        await self.ws.close()
        self.task.cancel()


async def join(port: int, ident: str, name: str) -> Peer:
    ws = await connect(f"ws://127.0.0.1:{port}/ws")
    peer = Peer(ws)
    await ws.send(json.dumps({"t": "hello", "id": ident, "name": name}))
    welcome = await peer.expect("welcome")
    assert welcome["name"] == name
    roster = await peer.expect("roster")
    assert any(p["id"] == ident for p in roster["people"])
    return peer


async def test_health_and_proxy() -> None:
    front, backend, watcher, room = await listen("127.0.0.1", 0, Room())
    assert front.sockets
    port = front.sockets[0].getsockname()[1]
    try:
        reader, writer = await asyncio.open_connection("127.0.0.1", port)
        writer.write(b"GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
        await writer.drain()
        body = await asyncio.wait_for(reader.read(), timeout=2)
        writer.close()
        assert b"200" in body and body.rstrip().endswith(b"ok"), body
        peer = await join(port, "health0000000001", "Health")
        await peer.close()
    finally:
        room.stop()
        watcher.cancel()
        front.close()
        await front.wait_closed()
        backend.close()
        await backend.wait_closed()


async def test_floor_and_audio(port: int) -> None:
    eric = "eric000000000001"
    alex = "alex000000000001"
    a = await join(port, eric, "Eric")
    b = await join(port, alex, "Alex")
    seen = await a.expect("roster")
    assert {p["name"] for p in seen["people"]} == {"Eric", "Alex"}

    await a.ws.send(json.dumps({"t": "ptt", "down": True}))
    floor = await a.expect("floor")
    assert floor["ok"] is True
    talk = await a.expect("talk")
    assert talk["down"] is True and talk["name"] == "Eric"
    await a.expect("roster")
    heard = await b.expect("talk")
    assert heard["id"] == eric and heard["down"] is True
    await b.expect("roster")

    await b.ws.send(json.dumps({"t": "ptt", "down": True}))
    denied = await b.expect("floor")
    assert denied["ok"] is False and denied["by"] == "Eric"

    frame = b"\x01\x00\x02\x00"
    await a.ws.send(frame)
    assert await b.next_bytes() == frame
    try:
        stray = await asyncio.wait_for(a.q.get(), 0.2)
    except TimeoutError:
        stray = None
    assert stray is None, stray

    await b.ws.send(b"\x03\x00")
    try:
        leaked = await asyncio.wait_for(a.q.get(), 0.2)
    except TimeoutError:
        leaked = None
    assert leaked is None, leaked

    await a.ws.send(json.dumps({"t": "ptt", "down": False}))
    end = await b.expect("talk")
    assert end["down"] is False
    await b.expect("roster")
    await a.expect("talk")
    await a.expect("roster")

    await b.ws.send(json.dumps({"t": "ptt", "down": True}))
    got = await b.expect("floor")
    assert got["ok"] is True
    await b.ws.send(json.dumps({"t": "ptt", "down": False}))
    await a.close()
    await b.close()


async def test_disconnect_clears_floor(port: int) -> None:
    eric = "eric000000000002"
    alex = "alex000000000002"
    a = await join(port, eric, "Eric")
    b = await join(port, alex, "Alex")
    await a.expect("roster")
    await a.ws.send(json.dumps({"t": "ptt", "down": True}))
    await a.expect("floor")
    await a.expect("talk")
    await a.expect("roster")
    await b.expect("talk")
    await b.expect("roster")
    await a.ws.close()
    end = await b.expect("talk")
    assert end["down"] is False
    roster = await b.expect("roster")
    assert roster["speaker"] is None
    assert [p["id"] for p in roster["people"]] == [alex]
    await b.close()


async def test_bad_name_and_replace(port: int) -> None:
    ws = await connect(f"ws://127.0.0.1:{port}/ws")
    await ws.send(json.dumps({"t": "hello", "id": "short", "name": "No"}))
    msg = json.loads(await ws.recv())
    assert msg["t"] == "error"
    await ws.wait_closed()

    ident = "eric000000000003"
    first = await join(port, ident, "Eric")
    ws = await connect(f"ws://127.0.0.1:{port}/ws")
    second = Peer(ws)
    await ws.send(json.dumps({"t": "hello", "id": ident, "name": "Eric Two"}))
    welcome = await second.expect("welcome")
    assert welcome["name"] == "Eric Two"
    roster = await second.expect("roster")
    assert [p["name"] for p in roster["people"]] == ["Eric Two"]
    await first.close()
    await second.close()


async def test_floor_timeout(port: int) -> None:
    ident = "eric000000000004"
    other = "alex000000000004"
    a = await join(port, ident, "Eric")
    b = await join(port, other, "Alex")
    await a.expect("roster")
    await a.ws.send(json.dumps({"t": "ptt", "down": True}))
    await a.expect("floor")
    await a.expect("talk")
    await a.expect("roster")
    await b.expect("talk")
    await b.expect("roster")
    await a.ws.send(b"\x01\x00")
    assert await b.next_bytes() == b"\x01\x00"
    await asyncio.sleep(0.9)
    timed = await a.expect("floor", timeout=2)
    assert timed["ok"] is False and timed["reason"] == "timeout"
    end = await b.expect("talk")
    assert end["down"] is False
    await a.close()
    await b.close()


async def main() -> None:
    room = Room(floor_audio_timeout=0.45, watch_interval=0.05)
    server, watcher = await serve_room("127.0.0.1", 0, room)
    sockets = server.sockets
    assert sockets
    port = sockets[0].getsockname()[1]
    try:
        await test_health_and_proxy()
        await test_floor_and_audio(port)
        await test_disconnect_clears_floor(port)
        await test_bad_name_and_replace(port)
        await test_floor_timeout(port)
    finally:
        room.stop()
        watcher.cancel()
        server.close()
        await server.wait_closed()
    print("relay tests passed")


if __name__ == "__main__":
    asyncio.run(main())
