#!/usr/bin/env python3
"""Run the local quote services and crxServer as one Docker service."""

import os
import signal
import subprocess
import sys
import time


def stop(children):
    for process, stop_signal in children:
        try:
            os.killpg(process.pid, stop_signal)
        except ProcessLookupError:
            pass

    deadline = time.monotonic() + 25
    for process, _ in children:
        try:
            process.wait(timeout=max(0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()


def main(server_id):
    stopping = False

    def request_stop(_signum, _frame):
        nonlocal stopping
        stopping = True

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    children = []
    commands = [
        ([sys.executable, "CoinbaseSocket.py"], signal.SIGTERM),
        ([sys.executable, "-c", "from BinanceKline import start_server; start_server(host='127.0.0.1')"], signal.SIGTERM),
        (["dotnet", "crxServer.dll", server_id], signal.SIGINT),
    ]
    try:
        for command, stop_signal in commands:
            children.append((subprocess.Popen(command, start_new_session=True), stop_signal))
        while not stopping:
            for process, _ in children:
                if process.poll() is not None:
                    print(f"{process.args[0]} exited with status {process.returncode}", file=sys.stderr)
                    return 1
            time.sleep(0.25)
        return 0
    finally:
        stop(children)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: start_server.py SERVER_ID")
    raise SystemExit(main(sys.argv[1]))
