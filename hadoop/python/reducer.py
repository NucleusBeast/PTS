#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys

current_key = None
current_sum = 0

for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        key, val = line.split("\t", 1)
        val = int(val)
    except:
        continue

    if current_key is None:
        current_key = key
        current_sum = val
    elif key == current_key:
        current_sum += val
    else:
        sys.stdout.write("%s\t%d\n" % (current_key, current_sum))
        current_key = key
        current_sum = val

# zadnji ključ
if current_key is not None:
    sys.stdout.write("%s\t%d\n" % (current_key, current_sum))
