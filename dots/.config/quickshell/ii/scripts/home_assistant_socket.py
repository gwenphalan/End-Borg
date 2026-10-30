#!/usr/bin/env python3
"""Line-delimited WebSocket transport for Quickshell; credentials arrive on stdin."""
import asyncio
import json
import sys


def emit(event, **fields):
    print(json.dumps(dict(event=event, **fields), separators=(',', ':')), flush=True)


async def connect(url, user_agent):
    import aiohttp
    reader = asyncio.StreamReader()
    loop = asyncio.get_running_loop()
    transport, _ = await loop.connect_read_pipe(
        lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    try:
        async with aiohttp.ClientSession(headers={'User-Agent': user_agent}, timeout=aiohttp.ClientTimeout(total=None, connect=10, sock_connect=10)) as client:
            async with client.ws_connect(url, heartbeat=30,
                                         timeout=aiohttp.ClientWSTimeout(ws_receive=45, ws_close=5)) as socket:
                emit('open')

                async def receive():
                    async for message in socket:
                        if message.type == aiohttp.WSMsgType.TEXT:
                            emit('message', message=message.data)
                        elif message.type == aiohttp.WSMsgType.ERROR:
                            raise ConnectionError('WebSocket receive failed')

                async def send():
                    while line := await reader.readline():
                        await socket.send_str(line.decode().rstrip('\r\n'))

                tasks = [asyncio.create_task(receive()), asyncio.create_task(send())]
                try:
                    done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                    for task in done:
                        task.result()
                finally:
                    for task in tasks:
                        task.cancel()
                    await asyncio.gather(*tasks, return_exceptions=True)
    finally:
        transport.close()


def main():
    try:
        if len(sys.argv) != 3:
            raise ValueError('Expected server URL and User-Agent')
        asyncio.run(connect(sys.argv[1], sys.argv[2]))
    except ImportError:
        emit('error', detail='Home Assistant transport requires python-aiohttp.')
        return 1
    except Exception as error:
        # Never log outgoing authentication frames or credentials.
        status = getattr(error, 'status', None)
        message = ('WebSocket handshake rejected (HTTP %s). Check server or proxy access rules.' % status
                   if status else 'Home Assistant connection failed (%s).' % type(error).__name__)
        emit('error', detail=message)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
