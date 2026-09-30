"""Print where each function and class sits in a Python file, so a reader can open one block.

usage (repo root): uv run --project server python tools/outline.py FILE [FILE...] [--min N]

One line per top-level function or class, and per method of a class:
    path:start-end  kind name  (N 行)
`start-end` are the line numbers to pass to a reader as offset and limit, so a 1000-line
file costs one outline plus the one block that matters. `--min N` hides entries shorter
than N lines. Only `.py` files; other types exit 2 rather than print a guess.
"""
import argparse
import ast
import sys
from pathlib import Path


def entries(tree):
    """Yield (depth, kind, name, start, end) for functions and classes, methods nested."""
    def walk(body, depth):
        for node in body:
            if isinstance(node, ast.ClassDef):
                yield depth, "class", node.name, node.lineno, node.end_lineno
                yield from walk(node.body, depth + 1)
            elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                kind = "async def" if isinstance(node, ast.AsyncFunctionDef) else "def"
                yield depth, kind, node.name, node.lineno, node.end_lineno

    yield from walk(tree.body, 0)


def outline(path, minimum=0):
    tree = ast.parse(Path(path).read_text(encoding="utf-8"), filename=str(path))
    lines = []
    for depth, kind, name, start, end in entries(tree):
        length = end - start + 1
        if length >= minimum:
            lines.append(f"{path}:{start}-{end}  {'  ' * depth}{kind} {name}  ({length} 行)")
    return lines


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("files", nargs="+")
    parser.add_argument("--min", type=int, default=0, dest="minimum")
    args = parser.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    status = 0
    for path in args.files:
        if Path(path).suffix != ".py":
            print(f"{path}: 只支援 .py", file=sys.stderr)
            status = 2
            continue
        print("\n".join(outline(path, args.minimum)))
    return status


if __name__ == "__main__":
    sys.exit(main())
