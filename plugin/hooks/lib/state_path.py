#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# 저장소에 복사한 공유 훅의 실행 상태를 둘 사용자별 폴더. 저장소 안에 두면 작업 트리가 더러워지고
# 팀원끼리 상태가 섞인다. 경로는 저장소 루트의 실제 경로로 갈라서 클론·워크트리마다 따로 둔다.
# 사용: state_path.py <저장소 루트>  → 폴더를 만들고 경로를 한 줄로 찍는다. 실패하면 exit 1.
import hashlib
import os
import sys


def state_path(repo_root):
    root = os.path.normcase(os.path.realpath(repo_root))
    if os.name == "nt":
        base = os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), "AppData", "Local")
    else:
        base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    digest = hashlib.sha256(root.encode("utf-8")).hexdigest()[:16]
    return os.path.join(base, "checkride", f"{os.path.basename(root)}-{digest}")


def main(argv):
    if len(argv) != 2 or not argv[1]:
        print("usage: state_path.py <repo-root>", file=sys.stderr)
        return 1
    root = os.path.normcase(os.path.realpath(argv[1]))
    path = os.path.normcase(os.path.realpath(state_path(argv[1])))
    try:
        inside_repo = os.path.commonpath([root, path]) == root
    except ValueError:
        inside_repo = False
    if inside_repo:
        print("state_path.py: state directory must be outside the repository", file=sys.stderr)
        return 1
    try:
        os.makedirs(path, mode=0o700, exist_ok=True)
    except OSError as exc:
        print(f"state_path.py: {exc}", file=sys.stderr)
        return 1
    print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
