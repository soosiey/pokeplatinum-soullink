"""Exercise the production cancellation helper with mocked engine services."""

import subprocess
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[2]


class StartupCancelTests(unittest.TestCase):
    def test_empty_and_existing_save_cancellation(self):
        source = (REPO / "src/game_start.c").read_text()
        signature = "static BOOL CancelSoulLinkGate(SaveData *saveData)\n{"
        start = source.index(signature)
        helper = source[start:source.index("\n}", start) + 2]
        harness = r'''
#include <assert.h>
typedef int BOOL;
typedef struct { BOOL backupExists, dataExists; int contents; } SaveData;
#define TRUE 1
#define FALSE 0
#define HEAP_ID_GAME_START 1
static int cancelled, cancels, closes, loads, clears;
BOOL SoulLinkGateUI_Cancelled(void) { return cancelled; }
void SoulLinkGate_Cancel(void) { cancels++; }
void SoulLinkGateUI_Close(void) { closes++; }
BOOL SaveData_BackupExists(SaveData *s) { return s->backupExists; }
BOOL SaveData_DataExists(SaveData *s) { return s->dataExists; }
void TryLoadingSave(int heap, SaveData *s) {
    assert(heap == HEAP_ID_GAME_START);
    assert(s->dataExists); /* Loading an empty save would reset the ROM. */
    loads++;
    s->contents = 42;
}
void SaveData_Clear(SaveData *s) { clears++; s->contents = 0; }
'''
        checks = r'''
int main(void) {
    SaveData save = { TRUE, FALSE, 7 };
    assert(!CancelSoulLinkGate(&save));
    assert(cancels == 0 && closes == 0 && loads == 0 && clears == 0);
    cancelled = TRUE;
    assert(CancelSoulLinkGate(&save));
    assert(loads == 0 && clears == 1 && save.contents == 0);
    assert(cancels == 1 && closes == 1);
    save.dataExists = TRUE;
    save.contents = 7; /* New Game changed RAM, but the old save is on disk. */
    assert(CancelSoulLinkGate(&save));
    assert(loads == 1 && clears == 1 && save.contents == 42);
    assert(cancels == 2 && closes == 2);
    return 0;
}
'''
        with tempfile.TemporaryDirectory(prefix="soullink-cancel-") as directory:
            path = Path(directory)
            (path / "test.c").write_text(harness + helper + checks)
            subprocess.run(["gcc", "-std=c99", "-Wall", "-Wextra", "-Werror",
                            str(path / "test.c"), "-o", str(path / "test")], check=True)
            subprocess.run([str(path / "test")], check=True)


if __name__ == "__main__":
    unittest.main()
