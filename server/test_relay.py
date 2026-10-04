#!/usr/bin/env python3
"""Floor control, roster, and audio routing for the Connect relay."""

from __future__ import annotations

import asyncio
import base64
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
    assert welcome["room"] == "Everyone"
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


async def assert_quiet(peer: Peer, pause: float = 0.2) -> None:
    try:
        stray = await asyncio.wait_for(peer.q.get(), pause)
    except TimeoutError:
        stray = None
    assert stray is None, stray


async def test_rooms_stay_separate(port: int) -> None:
    eric = "eric000000000010"
    ada = "ada0000000000010"
    cam = "cam0000000000010"
    a = await join(port, eric, "Eric")
    ws = await connect(f"ws://127.0.0.1:{port}/ws")
    b = Peer(ws)
    await ws.send(json.dumps({"t": "hello", "id": ada, "name": "Ada", "room": "Cabin"}))
    welcome = await b.expect("welcome")
    assert welcome["room"] == "Cabin"
    roster = await b.expect("roster")
    assert [p["name"] for p in roster["people"]] == ["Ada"]
    await assert_quiet(a)

    await a.ws.send(json.dumps({"t": "ptt", "down": True}))
    assert (await a.expect("floor"))["ok"] is True
    await a.expect("talk")
    await a.expect("roster")
    await b.ws.send(json.dumps({"t": "ptt", "down": True}))
    assert (await b.expect("floor"))["ok"] is True
    await b.expect("talk")
    await b.expect("roster")
    await assert_quiet(a)
    await a.ws.send(b"\x01\x00")
    await b.ws.send(b"\x02\x00")
    await assert_quiet(a, 0.15)
    await assert_quiet(b, 0.15)

    await a.ws.send(json.dumps({"t": "ptt", "down": False}))
    await b.ws.send(json.dumps({"t": "ptt", "down": False}))
    assert (await a.expect("talk"))["down"] is False
    await a.expect("roster")
    assert (await b.expect("talk"))["down"] is False
    await b.expect("roster")

    await a.ws.send(json.dumps({"t": "rooms"}))
    listed = await a.expect("rooms")
    assert {row["name"]: row["people"] for row in listed["rooms"]} == {
        "Everyone": 1,
        "Cabin": 1,
    }

    ws = await connect(f"ws://127.0.0.1:{port}/ws")
    c = Peer(ws)
    await ws.send(json.dumps({"t": "hello", "id": cam, "name": "Cam", "room": "Shed"}))
    assert (await c.expect("welcome"))["room"] == "Shed"
    await c.expect("roster")
    pushed = await a.expect("rooms")
    assert {row["name"] for row in pushed["rooms"]} == {"Everyone", "Cabin", "Shed"}
    await c.close()
    pushed = await a.expect("rooms")
    assert {row["name"] for row in pushed["rooms"]} == {"Everyone", "Cabin"}

    await a.ws.send(json.dumps({"t": "join", "room": "Cabin"}))
    assert (await a.expect("welcome"))["room"] == "Cabin"
    assert {p["name"] for p in (await a.expect("roster"))["people"]} == {"Eric", "Ada"}
    await a.expect("rooms")
    assert {p["name"] for p in (await b.expect("roster"))["people"]} == {"Eric", "Ada"}
    await b.ws.send(json.dumps({"t": "ptt", "down": True}))
    assert (await b.expect("floor"))["ok"] is True
    await b.expect("talk")
    await b.expect("roster")
    assert (await a.expect("talk"))["name"] == "Ada"
    await a.expect("roster")
    await b.ws.send(b"\x02\x00")
    assert await a.next_bytes() == b"\x02\x00"

    await a.ws.send(json.dumps({"t": "join", "room": "   "}))
    assert (await a.expect("error"))["code"] == "room"
    await a.close()
    await b.close()


async def test_room_limits() -> None:
    room = Room(max_rooms=1, max_people=2)
    server, watcher = await serve_room("127.0.0.1", 0, room)
    sockets = server.sockets
    assert sockets
    port = sockets[0].getsockname()[1]
    try:
        a = await join(port, "eric000000000011", "Eric")
        b = await join(port, "ada0000000000011", "Ada")
        await a.expect("roster")
        await b.ws.send(json.dumps({"t": "join", "room": "Cabin"}))
        assert (await b.expect("error"))["code"] == "rooms"
        await b.ws.send(json.dumps({"t": "ptt", "down": True}))
        assert (await b.expect("floor"))["ok"] is True
        assert (await a.expect("talk"))["name"] == "Ada"

        ws = await connect(f"ws://127.0.0.1:{port}/ws")
        await ws.send(json.dumps({"t": "hello", "id": "cam0000000000011", "name": "Cam"}))
        msg = json.loads(await ws.recv())
        assert msg["t"] == "error" and msg["code"] == "full"
        await ws.wait_closed()

        ws = await connect(f"ws://127.0.0.1:{port}/ws")
        await ws.send(
            json.dumps({"t": "hello", "id": "dee0000000000011", "name": "Dee", "room": " "})
        )
        msg = json.loads(await ws.recv())
        assert msg["t"] == "error" and msg["code"] == "room"
        await ws.wait_closed()
        await a.close()
        await b.close()
    finally:
        room.stop()
        watcher.cancel()
        server.close()
        await server.wait_closed()


async def test_photo_is_not_audio(port: int) -> None:
    eric = "eric000000000021"
    alex = "alex000000000021"
    jpeg = b"\xff\xd8" + b"\x00" * 8 + b"\xff\xd9"
    encoded = base64.b64encode(jpeg).decode()
    a = await join(port, eric, "Eric")
    b = await join(port, alex, "Alex")
    await a.expect("roster")
    await a.ws.send(json.dumps({"t": "photo", "jpeg": encoded, "id": "spoofed"}))
    seen = await b.expect("photo")
    assert seen["id"] == eric and base64.b64decode(seen["jpeg"]) == jpeg
    echo = await a.expect("photo")
    assert echo["id"] == eric

    cam = await join(port, "cam0000000000021", "Cam")
    forwarded = await cam.expect("photo")
    assert forwarded["id"] == eric
    await a.expect("roster")
    await b.expect("roster")

    await a.ws.send(json.dumps({"t": "photo", "jpeg": "!!!!"}))
    await a.ws.send(json.dumps({"t": "photo", "jpeg": ""}))
    assert (await a.expect("photo"))["jpeg"] == ""
    assert (await b.expect("photo"))["jpeg"] == ""
    assert (await cam.expect("photo"))["jpeg"] == ""

    huge = base64.b64encode(b"\xff\xd8" + b"\x00" * (24 * 1024)).decode()
    await a.ws.send(json.dumps({"t": "photo", "jpeg": huge}))
    await a.ws.send(json.dumps({"t": "ptt", "down": True}))
    assert (await a.expect("floor"))["ok"] is True
    await a.expect("talk")
    await a.expect("roster")
    await b.expect("talk")
    await b.expect("roster")
    await cam.expect("talk")
    await cam.expect("roster")
    await a.ws.send(b"\x01\x00")
    assert await b.next_bytes() == b"\x01\x00"
    try:
        stray = await asyncio.wait_for(a.q.get(), 0.2)
    except TimeoutError:
        stray = None
    assert stray is None, stray
    await a.close()
    await b.close()
    await cam.close()


async def test_chat_is_not_audio(port: int) -> None:
    eric = "eric000000000031"
    alex = "alex000000000031"
    a = await join(port, eric, "Eric")
    b = await join(port, alex, "Alex")
    await a.expect("roster")

    await a.ws.send(json.dumps({"t": "say", "text": "", "id": "spoofed"}))
    await a.ws.send(json.dumps({"t": "say", "text": "x" * 241}))
    await a.ws.send(json.dumps({"t": "say", "text": "bad\x00line"}))
    for i in range(41):
        await a.ws.send(json.dumps({"t": "say", "text": f"n{i}", "id": "spoofed"}))
        echo = await a.expect("say")
        seen = await b.expect("say")
        assert echo["id"] == eric and echo["name"] == "Eric" and echo["text"] == f"n{i}"
        assert seen["id"] == eric and seen["text"] == f"n{i}"

    cam = await join(port, "cam0000000000031", "Cam")
    logmsg = await cam.expect("chatlog")
    assert len(logmsg["lines"]) == 40
    assert logmsg["lines"][0]["text"] == "n1"
    assert logmsg["lines"][-1]["text"] == "n40"
    assert logmsg["lines"][-1]["id"] == eric
    await a.expect("roster")
    await b.expect("roster")

    await a.ws.send(json.dumps({"t": "ptt", "down": True}))
    assert (await a.expect("floor"))["ok"] is True
    await a.expect("talk")
    await a.expect("roster")
    await b.expect("talk")
    await b.expect("roster")
    await cam.expect("talk")
    await cam.expect("roster")
    await a.ws.send(b"\x02\x00")
    assert await b.next_bytes() == b"\x02\x00"
    assert await cam.next_bytes() == b"\x02\x00"

    await b.ws.send(json.dumps({"t": "join", "room": "Cabin"}))
    moved = await b.expect("welcome")
    assert moved["room"] == "Cabin"
    cabin = await b.expect("roster")
    assert [p["id"] for p in cabin["people"]] == [alex]
    await a.expect("roster")
    await cam.expect("roster")
    await a.ws.send(json.dumps({"t": "say", "text": "still here"}))
    assert (await cam.expect("say"))["text"] == "still here"
    await a.expect("say")
    await b.ws.send(json.dumps({"t": "ptt", "down": True}))
    assert (await b.expect("floor"))["ok"] is True

    await a.close()
    await b.close()
    await cam.close()
    await asyncio.sleep(0.4)
    dee = await join(port, "dee0000000000031", "Dee")
    await dee.ws.send(json.dumps({"t": "ptt", "down": True}))
    fresh = await dee.next_json()
    assert fresh["t"] == "floor" and fresh["ok"] is True, fresh
    await dee.close()


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
        await test_rooms_stay_separate(port)
        await test_room_limits()
        await test_photo_is_not_audio(port)
        await test_chat_is_not_audio(port)
    finally:
        room.stop()
        watcher.cancel()
        server.close()
        await server.wait_closed()
    print("relay tests passed")


if __name__ == "__main__":
    asyncio.run(main())
