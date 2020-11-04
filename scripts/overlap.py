#!/usr/bin/env python3
import string
import sys

CHARS = string.digits + string.punctuation + '¿¡' + string.whitespace

sents = set()
with open(sys.argv[1]) as test_file:
    sents = {line.strip(CHARS).lower() for line in test_file}
size_sents = len(sents)

count = 0
for line in sys.stdin:
    segment = line.strip(CHARS).lower()
    if segment in sents:
        count += 1
        sents.remove(segment)
        sys.stderr.write('Found line: ' + line)
print('Overlap % with {}: {:.3f}'.format(sys.argv[1], count/size_sents*100))
