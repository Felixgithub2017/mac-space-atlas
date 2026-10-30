import os
import tempfile
import unittest
from pathlib import Path

from app import ScanState, scan_directory


class ScannerTests(unittest.TestCase):
    def test_totals_navigation_and_links(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "photos").mkdir()
            (root / "photos" / "picture.bin").write_bytes(b"x" * 8192)
            (root / "note.txt").write_bytes(b"hello")
            os.link(root / "note.txt", root / "note-copy.txt")
            (root / "shortcut").symlink_to(root / "photos", target_is_directory=True)

            result = scan_directory(directory)
            expected = ((root / "photos" / "picture.bin").stat().st_blocks +
                        (root / "note.txt").stat().st_blocks) * 512
            self.assertEqual(result["root"]["size"], expected)
            self.assertEqual(result["counts"]["files"], 3)
            self.assertEqual(result["counts"]["links"], 1)

            state = ScanState()
            state.result = result
            top = state.folder(directory)
            self.assertEqual(top["entries"][0]["name"], "photos")
            self.assertEqual(top["total_items"], 3)
            self.assertEqual(state.folder(directory, query="note")["filtered_items"], 2)
            self.assertEqual(state.folder(str(root / "photos"))["size"],
                             (root / "photos" / "picture.bin").stat().st_blocks * 512)
            with self.assertRaises(ValueError):
                state.folder(str(root.parent))

    def test_empty_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            result = scan_directory(directory)
            self.assertEqual(result["root"]["size"], 0)
            self.assertEqual(result["counts"]["files"], 0)

    def test_treemap_remainder_and_pagination(self):
        with tempfile.TemporaryDirectory() as directory:
            for number in range(83):
                (Path(directory) / ("file-%02d" % number)).write_bytes(b"x")
            state = ScanState()
            state.result = scan_directory(directory)
            first = state.folder(directory)
            self.assertEqual(len(first["entries"]), 80)
            self.assertEqual(len(state.folder(directory, page=1)["entries"]), 3)
            self.assertEqual(sum(item["size"] for item in first["treemap"]), first["size"])
            self.assertEqual(first["treemap"][-1]["name"], "其他项目")


if __name__ == "__main__":
    unittest.main()
