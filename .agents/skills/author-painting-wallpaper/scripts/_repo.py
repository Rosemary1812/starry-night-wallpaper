"""Small, deliberately strict readers for this repository's Swift catalog."""
import hashlib
import json
from pathlib import Path
import re


def text(root, name):
    return (Path(root) / name).read_text(encoding='utf-8')


def block(source, marker):
    start = source.find(marker)
    if start < 0:
        raise ValueError('Unsupported source layout; missing ' + marker)
    start = source.find('{', start) + 1
    depth = 1
    # Catalog/parameter blocks have no braces inside string literals today.
    for index in range(start, len(source)):
        if source[index] == '{':
            depth += 1
        elif source[index] == '}':
            depth -= 1
            if depth == 0:
                return source[start:index]
    raise ValueError('Unclosed block: ' + marker)


def catalog(root):
    source = text(root, 'Artwork.swift')
    head = block(source, 'enum Artwork:').split('var ', 1)[0]
    cases = []
    for declaration in re.findall(r'^\s*case ([^\n]+)', head, re.M):
        for case in declaration.split('//', 1)[0].split(','):
            case = case.strip()
            if not re.fullmatch(r'[A-Za-z][A-Za-z0-9]*', case):
                raise ValueError('Unsupported enum case declaration: ' + case)
            cases.append(case)
    if not cases or len(set(cases)) != len(cases):
        raise ValueError('Empty or duplicate artwork cases')
    arrays = {}
    for field in ['filename', 'title', 'shortName', 'year', 'description']:
        body = block(source, 'var ' + field + ': String')
        match = re.search(r'\[\s*(".*")\s*\]\[rawValue\]', body, re.S)
        if not match:
            raise ValueError('Unsupported metadata representation: ' + field)
        values = re.findall(r'"(?:[^"\\]|\\.)*"', match.group(1))
        arrays[field] = [json.loads(value) for value in values]
        if len(values) != len(cases):
            raise ValueError(f'{field}: {len(values)} entries for {len(cases)} cases')
    slugs = arrays['filename']
    if len(set(slugs)) != len(slugs) or any(not re.fullmatch('[a-z0-9-]+', s) for s in slugs):
        raise ValueError('Invalid or duplicate asset slugs')
    return [dict(id=i, case=case, **{k: v[i] for k, v in arrays.items()}) for i, case in enumerate(cases)]


def digest(path):
    hasher = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            hasher.update(chunk)
    return hasher.hexdigest()
