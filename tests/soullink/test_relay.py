import asyncio
import contextlib
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import soullink_bridge as bridge


def framed(payload):
    return str(len(payload)).encode() + b" " + payload


class RelayTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.relay = bridge.SoulLinkRelay()
        self.tasks, self.writers = set(), []

        async def handle(reader, writer):
            task = asyncio.current_task()
            self.tasks.add(task)
            try:
                await self.relay.handle(reader, writer)
            finally:
                self.tasks.remove(task)

        self.server = await asyncio.start_server(handle, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]

    async def asyncTearDown(self):
        self.server.close()
        for writer in self.writers:
            writer.close()
            with contextlib.suppress(ConnectionError):
                await writer.wait_closed()
        for task in list(self.tasks):
            task.cancel()
        await asyncio.gather(*list(self.tasks), return_exceptions=True)
        await asyncio.wait_for(self.server.wait_closed(), 2)

    async def connect(self, role):
        reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
        self.writers.append(writer)
        await bridge.write_frame(writer, f"SL1|1|{role}|HELLO|258".encode())
        return reader, writer

    async def receive(self, reader):
        return await asyncio.wait_for(bridge.read_frame(reader), 2)

    async def test_pairing_keepalive_capacity_and_role_validation(self):
        host, host_writer = await self.connect("host")
        clients = []
        for index in range(1, 4):
            reader, writer = await self.connect("client")
            clients.append((reader, writer))
            self.assertEqual(await self.receive(reader),
                             f"SL1|1|relay|WELCOME|client{index}".encode())
            self.assertEqual(await self.receive(reader), b"SL1|1|host|HELLO|258")
            self.assertEqual(await self.receive(host),
                             f"SL1|1|client{index}|HELLO|258".encode())
        await bridge.write_frame(host_writer, b"SL1|2|host|KEEPALIVE|60")
        for reader, writer in clients:
            self.assertEqual(await self.receive(reader), b"SL1|2|host|KEEPALIVE|60")
        await bridge.write_frame(clients[0][1], b"SL1|2|client|KEEPALIVE|61")
        self.assertEqual(await self.receive(host), b"SL1|2|client1|KEEPALIVE|61")
        for role in ("client", "host"):
            rejected, _ = await self.connect(role)
            self.assertEqual(await asyncio.wait_for(rejected.read(1), 2), b"")
        await bridge.write_frame(clients[0][1], b"SL1|3|host|KEEPALIVE|62")
        self.assertEqual(await asyncio.wait_for(clients[0][0].read(1), 2), b"")
        replacement, _ = await self.connect("client")
        self.assertEqual(await self.receive(replacement), b"SL1|1|relay|WELCOME|client1")
        self.assertEqual(await self.receive(replacement), b"SL1|1|host|HELLO|258")
        self.assertEqual(await self.receive(host), b"SL1|1|client1|HELLO|258")

    async def test_client_before_host_and_fragmented_coalesced_frames(self):
        client, writer = await self.connect("client")
        self.assertEqual(await self.receive(client), b"SL1|1|relay|WELCOME|client1")
        host, _ = await self.connect("host")
        self.assertEqual(await self.receive(host), b"SL1|1|client1|HELLO|258")
        self.assertEqual(await self.receive(client), b"SL1|1|host|HELLO|258")
        payload = b"SL1|2|client|KEEPALIVE|60"
        wire = framed(payload)
        for fragment in (wire[:1], wire[1:4], wire[4:]):
            writer.write(fragment)
            await writer.drain()
            await asyncio.sleep(0)
        self.assertEqual(await self.receive(host), b"SL1|2|client1|KEEPALIVE|60")
        writer.write(framed(b"SL1|3|client|KEEPALIVE|61")
                     + framed(b"SL1|4|client|KEEPALIVE|62"))
        await writer.drain()
        for sequence, frame in ((3, 61), (4, 62)):
            self.assertEqual(await self.receive(host),
                             f"SL1|{sequence}|client1|KEEPALIVE|{frame}".encode())

    async def test_frame_validation(self):
        for wire in (b"0 ", b"65537 ", b"x ", b"00000000001 x"):
            reader = asyncio.StreamReader()
            reader.feed_data(wire)
            reader.feed_eof()
            with self.subTest(wire=wire), self.assertRaises(ValueError):
                await bridge.read_frame(reader)
        reader = asyncio.StreamReader()
        reader.feed_data(b"4 ab")
        reader.feed_eof()
        with self.assertRaises(asyncio.IncompleteReadError):
            await bridge.read_frame(reader)
