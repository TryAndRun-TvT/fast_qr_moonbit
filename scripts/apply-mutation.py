#!/usr/bin/env python3
"""apply-mutation.py —— 把一条变异植入源码（S10 附录 E / scripts/test-audit.sh 内部用）。
用法: python3 scripts/apply-mutation.py <文件> <原文> <替换>
退出码：0 植入成功；3 锚点未找到。"""
import sys

path, frm, to = sys.argv[1], sys.argv[2], sys.argv[3]
# shell 侧用 \n 传递多行锚点，此处还原
frm = frm.encode().decode('unicode_escape')
to = to.encode().decode('unicode_escape')
s = open(path, encoding='utf-8').read()
if frm not in s:
    print(f'anchor not found in {path}', file=sys.stderr)
    sys.exit(3)
open(path, 'w', encoding='utf-8').write(s.replace(frm, to, 1))
