#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# 중괄호 없는 변수 뒤에 비ASCII 글자가 바로 붙은 곳을 찾는다.
# bash 는 "$n개" 를 변수 n개 로 읽는다. set -u 아래서는 그 자리에서 죽는다.
# 주석과 이스케이프한 \$ 는 대상이 아니다.
import glob, io, os, re, sys

PAT = re.compile(r'(?<!\\)\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]')

def main() -> int:
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    pats = ["plugin/hooks/*.sh", "plugin/hooks/*/*.sh", "tests/*.sh", "tests/*/*.sh",
            ".githooks/*", "setup.sh"]
    out = []
    for g in pats:
        for p in sorted(glob.glob(os.path.join(root, g))):
            if not os.path.isfile(p):
                continue
            for i, line in enumerate(io.open(p, encoding="utf-8", errors="replace"), 1):
                if line.lstrip().startswith("#"):
                    continue
                for m in PAT.finditer(line):
                    out.append("%s:%d %s" % (os.path.relpath(p, root), i, m.group(0)))
    if out:
        print("\n".join(out))
    return 0

if __name__ == "__main__":
    sys.exit(main())
