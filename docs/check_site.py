"""Check built links, or verify every deployed file against a build manifest."""
import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import time
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urljoin, urlsplit
from urllib.request import urlopen


class Page(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.links, self.ids = [], set()
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.add(attrs["id"])
        for key in ("href", "src"):
            if attrs.get(key):
                self.links.append(attrs[key])


def local_check(root, base):
    pages = {p.relative_to(root).as_posix(): Page(p.read_text()) for p in root.rglob("*.html")}
    failures = []
    for name, page in pages.items():
        for link in page.links:
            original = urlsplit(link)
            if original.scheme or original.netloc:
                continue
            target = urlsplit(urljoin(base + name, link))
            path = unquote(target.path)
            if not path.startswith(base):
                failures.append(f"{name}: URL escapes site base: {link}")
                continue
            relative = path[len(base):]
            if not relative or relative.endswith("/"):
                relative += "index.html"
            destination = root / relative
            if not destination.is_file() and not destination.suffix:
                relative += ".html"
                destination = root / relative
            if not destination.is_file():
                failures.append(f"{name}: missing {link}")
            elif target.fragment and relative in pages and unquote(target.fragment) not in pages[relative].ids:
                failures.append(f"{name}: missing anchor {link}")
    if failures:
        raise SystemExit("\n".join(failures))
    print(f"Local links: {len(pages)} HTML pages passed")


def write_manifest(root, revision):
    files = {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in sorted(root.rglob("*")) if p.is_file() and p.name != "site-manifest.json"}
    (root / "site-manifest.json").write_text(json.dumps({"revision": revision, "files": files}, indent=2) + "\n")
    print(f"Site manifest: {len(files)} files")


def fetch(url):
    with urlopen(url, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f"HTTP {response.status}: {url}")
        return response.read()


def deployed_check(url, revision, wait):
    url = url.rstrip("/") + "/"
    deadline = time.monotonic() + wait
    while True:
        try:
            manifest = json.loads(fetch(url + "site-manifest.json"))
            if manifest["revision"] == revision:
                break
            problem = f"deployed revision is {manifest['revision']}, expected {revision}"
        except (HTTPError, URLError, ValueError) as error:
            problem = str(error)
        if time.monotonic() >= deadline:
            raise SystemExit(problem)
        time.sleep(10)
    for name, digest in manifest["files"].items():
        actual = hashlib.sha256(fetch(urljoin(url, name))).hexdigest()
        if actual != digest:
            raise SystemExit(f"Content mismatch: {name}")
    print(f"Deployment: {len(manifest['files'])} pages/assets match revision {revision}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path)
    parser.add_argument("--base", default="/AlgebraOfVega.jl/dev/")
    parser.add_argument("--revision", required=True)
    parser.add_argument("--url")
    parser.add_argument("--wait", type=int, default=0)
    args = parser.parse_args()
    if args.root:
        local_check(args.root, args.base)
        write_manifest(args.root, args.revision)
    if args.url:
        deployed_check(args.url, args.revision, args.wait)
