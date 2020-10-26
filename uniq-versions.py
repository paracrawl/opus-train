#!/usr/bin/env python3
import sys
import re

version_regex = re.compile('_v.*')
prev = ""
for line in sys.stdin:
    if version_regex.sub('',line) == prev:
        continue
    else:
        prev = version_regex.sub('',line)
        sys.stdout.write(line)
