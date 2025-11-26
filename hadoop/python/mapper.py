#!/usr/bin/env python
# -*- coding: utf-8 -*-

import sys


def parse_csv_line(line):
    # Preprost CSV split (brez narekovajev v podatkih)
    return [x.strip() for x in line.rstrip("\n").split(",")]


for i, line in enumerate(sys.stdin):
    if i == 0 and line.lower().startswith("id,"):
        # preskoči header
        continue
    parts = parse_csv_line(line)
    # pričakujemo 11 stolpcev:
    # id,title,description,currentValue,targetValue,unit,completed,date,isPunishment,isManualTask,createdAt
    if len(parts) < 11:
        continue
    title = parts[1]
    completed = parts[6].lower()  # 'true' ali 'false'
    if title:
        # ključ: title|completed
        sys.stdout.write("%s\t1\n" % ("%s|%s" % (title, completed)))
