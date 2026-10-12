import argparse
import asyncio
import contextlib
import io
import sys
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import soullink_bridge as bridge


class LauncherTests(unittest.TestCase):
    def test_cli_default_and_supported_counts(self):
        for count in (None, 1, 2, 3, 4):
            args = ["bridge", "--emuhawk", "EmuHawk.exe"]
            if count is not None:
                args += ["--instances", str(count)]
            with patch.object(sys, "argv", args), patch.object(sys, "platform", "win32"), \
                    patch.object(bridge, "is_wsl", return_value=False), \
                    patch.object(bridge, "run", new_callable=AsyncMock) as run:
                bridge.main()
                run.assert_awaited_once_with("0.0.0.0", 7777, "EmuHawk.exe", count or 1)

    def test_invalid_counts_and_missing_executable(self):
        for extra in (["--instances", "0"], ["--instances", "5"],
                      ["--instances", "-1"], ["--instances", "two"],
                      ["--instances", "2"]):
            with patch.object(sys, "argv", ["bridge", *extra]), \
                    contextlib.redirect_stderr(io.StringIO()), \
                    self.assertRaises(SystemExit) as result:
                bridge.main()
            self.assertEqual(result.exception.code, 2)

    def test_launch_count_and_socket_arguments(self):
        for count in (1, 2, 3, 4):
            server = AsyncMock()
            server.sockets = []
            with patch.object(bridge.asyncio, "start_server", return_value=server) as start, \
                    patch.object(bridge.subprocess, "Popen") as launch:
                def launched(*args):
                    start.assert_awaited_once()
                    return Mock(pid=123)
                launch.side_effect = launched
                asyncio.run(bridge.run("127.0.0.1", 8888, "EmuHawk.exe", count))
                self.assertEqual(launch.call_count, count)
                for call in launch.call_args_list:
                    self.assertEqual(call.args[0],
                                     ["EmuHawk.exe", "--socket-ip=127.0.0.1", "--socket-port=8888"])

    def test_wsl_forwards_instance_count(self):
        args = argparse.Namespace(bind="0.0.0.0", port=7777, emuhawk="EmuHawk.exe", instances=4)
        with patch.object(bridge.shutil, "which", return_value="py.exe"), \
                patch.object(bridge.subprocess, "run", return_value=Mock(stdout="python.exe")), \
                patch.object(bridge, "wsl_path", side_effect=lambda path: path), \
                patch.object(bridge, "windows_path", side_effect=lambda path: path), \
                patch.object(bridge.subprocess, "Popen") as launch:
            launch.return_value.wait.return_value = 0
            self.assertEqual(bridge.run_on_windows(args), 0)
            command = launch.call_args.args[0]
            self.assertEqual(command[command.index("--instances") + 1], "4")


if __name__ == "__main__":
    unittest.main()
