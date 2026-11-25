#!/usr/bin/env python3
"""Static cross-reference check for a Monkey C project.

Neither pass executes the Garmin toolchain:

 1. Project symbols: every `Thing.member` reference where `Thing` is a module
    or class declared in this project must resolve to a declaration in it,
    and the call's argument count must match the declaration.
 2. SDK symbols: every `Mod.MEMBER` reference where `Mod` is an imported
    Toybox module must appear in that module's bundled API documentation.
"""
import os
import re
import sys
from collections import defaultdict

SRC_DIR, DOC_DIR = sys.argv[1], sys.argv[2]
FILES = sorted(f for f in os.listdir(SRC_DIR) if f.endswith('.mc'))


def strip_noise(text):
    """Blank out literals and comments, preserving line structure.

    String literals go FIRST: a URL like "https://x" otherwise loses its
    closing quote to the line-comment rule, and the damage cascades.
    """
    text = re.sub(r'"(\\.|[^"\\\n])*"', '""', text)
    text = re.sub(r"'(\\.|[^'\\\n])'", "' '", text)
    text = re.sub(r'/\*.*?\*/', lambda m: '\n' * m.group(0).count('\n'), text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    return text


def params_of(line, open_paren):
    """Argument list of a call/declaration starting at the given '(' index.

    Returns a list of argument source strings, or None if the parens do not
    close on this line (multi-line call: skip rather than guess).
    """
    depth, args, buf = 0, [], ''
    for ch in line[open_paren:]:
        if ch in '([<' and ch == '(':
            depth += 1
            if depth == 1:
                continue
        elif ch == ')':
            depth -= 1
            if depth == 0:
                if buf.strip():
                    args.append(buf)
                return args
        if depth == 1 and ch == ',':
            args.append(buf)
            buf = ''
            continue
        buf += ch
    return None


# ------------------------------------------------------------------- pass 1
decls = defaultdict(dict)
kinds, raw, clean = {}, {}, {}

for name in FILES:
    raw[name] = open(os.path.join(SRC_DIR, name)).read()
    body = strip_noise(raw[name])
    clean[name] = body
    stack, depth = [], 0
    for line in body.split('\n'):
        head = re.match(r'\s*(module|class)\s+(\w+)', line)
        if head:
            stack.append((head.group(2), depth))
            kinds[head.group(2)] = head.group(1)

        fn = re.match(r'\s*(?:\(:[^)]*\)\s*)*(?:public\s+|private\s+|hidden\s+|static\s+)*function\s+(\w+)\s*\(', line)
        if fn and stack:
            args = params_of(line, line.index('(', fn.end(1)))
            decls[stack[-1][0]][fn.group(1)] = None if args is None else len(args)

        cv = re.match(r'\s*(?:public\s+|private\s+|hidden\s+)*(?:const|var|enum)\s+(\w+)', line)
        if cv and stack:
            decls[stack[-1][0]][cv.group(1)] = 'field'

        depth += line.count('{') - line.count('}')
        while stack and depth <= stack[-1][1]:
            stack.pop()

owners = set(decls)
problems = []

for name in FILES:
    for lineno, line in enumerate(clean[name].split('\n'), 1):
        for m in re.finditer(r'\b([A-Z]\w+)\.(\w+)\s*(\()?', line):
            holder, member, is_call = m.group(1), m.group(2), m.group(3)
            if holder not in owners:
                continue
            if member not in decls[holder]:
                problems.append("%s:%d  %s.%s is not declared in %s"
                                % (name, lineno, holder, member, holder))
                continue
            want = decls[holder][member]
            if is_call and isinstance(want, int):
                args = params_of(line, m.end() - 1)
                if args is not None and len(args) != want:
                    problems.append("%s:%d  %s.%s called with %d arg(s), declared %d"
                                    % (name, lineno, holder, member, len(args), want))

# ------------------------------------------------------------------- pass 2
def text_of(path):
    html = open(path, encoding='utf-8', errors='replace').read()
    html = re.sub(r'<(script|style)\b.*?</\1>', ' ', html, flags=re.S | re.I)
    return re.sub(r'<[^>]+>', ' ', html)


def doc_members(module):
    paths = [os.path.join(DOC_DIR, module + '.html')]
    sub = os.path.join(DOC_DIR, module)
    extra = set()
    if os.path.isdir(sub):
        for f in os.listdir(sub):
            if f.endswith('.html'):
                paths.append(os.path.join(sub, f))
                extra.add(os.path.splitext(f)[0])
    found = set(extra)
    for p in paths:
        if not os.path.exists(p):
            continue
        txt = text_of(p)
        found |= set(re.findall(r'\b([A-Z][A-Z0-9_]{2,})\b', txt))   # constants
        found |= set(re.findall(r'\b(\w+)\s*\(', txt))                # functions
        found |= set(re.findall(r'\b(\w+)\s+as\s+', txt))             # typedefs/vars
    return found


cache, unknown = {}, []
for name in FILES:
    imports = set(re.findall(r'import\s+Toybox\.(\w+)\s*;', raw[name]))
    for lineno, line in enumerate(clean[name].split('\n'), 1):
        for m in re.finditer(r'\b([A-Z]\w+)\.(\w+)', line):
            mod, member = m.group(1), m.group(2)
            if mod in owners or mod not in imports:
                continue
            if mod not in cache:
                cache[mod] = doc_members(mod)
            if cache[mod] and member not in cache[mod]:
                unknown.append("%s:%d  %s.%s not in SDK docs for Toybox.%s"
                               % (name, lineno, mod, member, mod))

print("=== project symbol / arity problems ===")
print('\n'.join(problems) if problems else "none")
print("\n=== SDK symbols not found in bundled docs ===")
print('\n'.join(unknown) if unknown else "none")
print("\n=== brace balance (on correctly stripped source) ===")
for name in FILES:
    b = clean[name]
    ok = b.count('{') == b.count('}') and b.count('(') == b.count(')') and b.count('[') == b.count(']')
    print("  %-26s %s" % (name, "OK" if ok else "UNBALANCED"))
print("\nchecked %d files; owners: %s" % (len(FILES), ', '.join(sorted(owners))))
