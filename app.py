#!/usr/bin/env python3
"""Local, read-only disk usage explorer."""

import argparse
import heapq
import json
import os
import shutil
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


HERE = Path(__file__).resolve().parent
HOME = str(Path.home())


def disk_space():
    usage = shutil.disk_usage(HOME)
    return {"total": usage.total, "used": usage.used, "free": usage.free}


def scan_directory(root_path, progress=None):
    """Walk without following links; count allocated blocks, not apparent size."""
    root_path = os.path.abspath(os.path.expanduser(root_path))
    root = {"name": os.path.basename(root_path) or "/", "path": root_path,
            "size": 0, "folders": {}, "files": []}
    folders = {root_path: root}
    largest = []
    seen_files = set()
    counts = {"files": 0, "folders": 0, "skipped": 0, "links": 0}
    sequence = 0
    stack = [(root, False)]

    while stack:
        node, finished = stack.pop()
        if finished:
            node["size"] += sum(child["size"] for child in node["folders"].values())
            continue
        stack.append((node, True))
        try:
            with os.scandir(node["path"]) as entries:
                for entry in entries:
                    try:
                        info = entry.stat(follow_symlinks=False)
                        if entry.is_symlink():
                            counts["links"] += 1
                            continue
                        if entry.is_dir(follow_symlinks=False):
                            # These paths mirror the startup disk or point at other volumes.
                            if root_path == "/" and entry.path in ("/System/Volumes", "/Volumes"):
                                counts["skipped"] += 1
                                continue
                            child = {"name": entry.name, "path": entry.path,
                                     "size": 0, "folders": {}, "files": []}
                            node["folders"][entry.name] = child
                            folders[entry.path] = child
                            counts["folders"] += 1
                            stack.append((child, False))
                        elif entry.is_file(follow_symlinks=False):
                            size = info.st_blocks * 512 if hasattr(info, "st_blocks") else info.st_size
                            if info.st_nlink > 1:
                                identity = (info.st_dev, info.st_ino)
                                if identity in seen_files:
                                    size = 0
                                else:
                                    seen_files.add(identity)
                            node["files"].append((entry.name, size))
                            node["size"] += size
                            counts["files"] += 1
                            sequence += 1
                            if len(largest) < 40 or size > largest[0][0]:
                                item = {"name": entry.name, "path": entry.path, "size": size}
                                if len(largest) < 40:
                                    heapq.heappush(largest, (size, sequence, item))
                                else:
                                    heapq.heapreplace(largest, (size, sequence, item))
                        if progress and (counts["files"] + counts["folders"]) % 300 == 0:
                            progress(counts, node["path"])
                    except OSError:
                        counts["skipped"] += 1
        except OSError:
            counts["skipped"] += 1
    return {"root": root, "folders": folders, "counts": counts,
            "largest": [item for _, _, item in sorted(largest, reverse=True)]}


class ScanState:
    def __init__(self):
        self.lock = threading.Lock()
        self.status = {"phase": "idle", "path": HOME, "counts": {},
                       "current": "", "elapsed": 0}
        self.result = None
        self.started = 0

    def start(self, path):
        if not path.strip():
            raise ValueError("请输入文件夹路径")
        path = os.path.abspath(os.path.expanduser(path))
        if not os.path.isdir(path):
            raise ValueError("目录不存在或无法访问")
        with self.lock:
            if self.status["phase"] == "scanning":
                raise ValueError("已有扫描正在进行，请稍候")
            self.result = None
            self.started = time.monotonic()
            self.status = {"phase": "scanning", "path": path, "counts": {},
                           "current": path, "elapsed": 0}
        threading.Thread(target=self._run, args=(path,), daemon=True).start()

    def _run(self, path):
        def update(counts, current):
            with self.lock:
                self.status["counts"] = counts.copy()
                self.status["current"] = current
                self.status["elapsed"] = round(time.monotonic() - self.started, 1)

        try:
            result = scan_directory(path, update)
            with self.lock:
                self.result = result
                self.status.update(phase="complete", counts=result["counts"],
                                   current="", elapsed=round(time.monotonic() - self.started, 1))
        except Exception as error:
            with self.lock:
                self.status.update(phase="error", error=str(error))

    def snapshot(self):
        with self.lock:
            return dict(self.status)

    def folder(self, path, query="", page=0):
        with self.lock:
            result = self.result
        if result is None:
            raise ValueError("请先完成扫描")
        node = result["folders"].get(path)
        if node is None:
            raise ValueError("文件夹不在当前扫描范围内")
        children = [{"name": child["name"], "path": child["path"],
                     "size": child["size"], "type": "folder",
                     "items": len(child["folders"]) + len(child["files"])}
                    for child in node["folders"].values()]
        children.extend({"name": name, "path": os.path.join(path, name),
                         "size": size, "type": "file"} for name, size in node["files"])
        children.sort(key=lambda item: (-item["size"], item["name"].lower()))
        visible = [item for item in children if query.lower() in item["name"].lower()] if query else children
        offset = max(page, 0) * 80
        treemap = children[:11]
        if len(children) > 11:
            treemap.append({"name": "其他项目", "size": sum(item["size"] for item in children[11:]),
                            "type": "other", "path": "", "items": len(children) - 11})
        return {"path": node["path"], "name": node["name"], "size": node["size"],
                "parent": os.path.dirname(path) if path != result["root"]["path"] else None,
                "total_items": len(children), "filtered_items": len(visible),
                "entries": visible[offset:offset + 80], "treemap": treemap,
                "largest": result["largest"] if path == result["root"]["path"] else [],
                "counts": result["counts"], "root_path": result["root"]["path"]}


STATE = ScanState()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def send_json(self, data, code=200):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        try:
            if parsed.path == "/api/status":
                self.send_json({"scan": STATE.snapshot(), "disk": disk_space(), "home": HOME})
            elif parsed.path == "/api/folder":
                self.send_json(STATE.folder(params.get("path", [""])[0],
                                            params.get("query", [""])[0],
                                            int(params.get("page", ["0"])[0])))
            elif parsed.path in ("/", "/index.html", "/styles.css", "/app.js"):
                filename = "index.html" if parsed.path == "/" else parsed.path.lstrip("/")
                content = (HERE / filename).read_bytes()
                mime = {"html": "text/html", "css": "text/css", "js": "text/javascript"}
                self.send_response(200)
                self.send_header("Content-Type", mime[filename.rsplit(".", 1)[-1]] + "; charset=utf-8")
                self.send_header("Content-Length", str(len(content)))
                self.end_headers()
                self.wfile.write(content)
            else:
                self.send_error(404)
        except (ValueError, OSError) as error:
            self.send_json({"error": str(error)}, 400)

    def do_POST(self):
        if self.path != "/api/scan":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > 4096:
                raise ValueError("请求过大")
            payload = json.loads(self.rfile.read(length))
            path = payload.get("path", HOME)
            if not isinstance(path, str):
                raise ValueError("请输入有效的文件夹路径")
            STATE.start(path)
            self.send_json({"ok": True})
        except (ValueError, OSError, json.JSONDecodeError) as error:
            self.send_json({"error": str(error)}, 400)


def main():
    parser = argparse.ArgumentParser(description="本机磁盘空间可视化工具")
    parser.add_argument("--port", type=int, default=8766)
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print("磁盘空间地图已启动：http://127.0.0.1:%s" % args.port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
