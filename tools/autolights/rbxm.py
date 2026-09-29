import struct, sys, os, re, lz4.block

def read_chunks(data):
    assert data[:8] == b'<roblox!', 'not an rbxm'
    pos = 8 + 6
    version, ncls, ninst = struct.unpack_from('<Hii', data, pos); pos += 2 + 4 + 4 + 8
    chunks = []
    while pos < len(data):
        name = data[pos:pos+4]; comp, uncomp, _ = struct.unpack_from('<III', data, pos+4); pos += 16
        if comp:
            payload = lz4.block.decompress(data[pos:pos+comp], uncompressed_size=uncomp); pos += comp
        else:
            payload = data[pos:pos+uncomp]; pos += uncomp
        chunks.append((name, payload))
        if name == b'END\x00': break
    return chunks

def u32(b, p): return struct.unpack_from('<I', b, p)[0]
def rstr(b, p):
    n = u32(b, p); return b[p+4:p+4+n], p+4+n

def deinterleave_i32(b, p, n, delta):
    raw = b[p:p+4*n]
    vals = []
    for i in range(n):
        v = (raw[i] << 24) | (raw[n+i] << 16) | (raw[2*n+i] << 8) | raw[3*n+i]
        v = (v >> 1) ^ -(v & 1)   # zigzag
        vals.append(v)
    if delta:
        acc = 0
        for i in range(n):
            acc += vals[i]; vals[i] = acc
    return vals, p + 4*n

def parse(path):
    data = open(path, 'rb').read()
    classes = {}     # class id -> (name, [referents])
    props = {}       # referent -> {prop: value}
    parent = {}
    for name, b in read_chunks(data):
        if name == b'INST':
            cid = u32(b, 0); cname, p = rstr(b, 4)
            is_service = b[p]; p += 1
            n = u32(b, p); p += 4
            refs, p = deinterleave_i32(b, p, n, True)
            classes[cid] = (cname.decode(), refs)
        elif name == b'PROP':
            cid = u32(b, 0); pname, p = rstr(b, 4); pname = pname.decode()
            typ = b[p]; p += 1
            cname, refs = classes[cid]
            if typ == 0x01 and pname in ('Name', 'Source', 'ScriptGuid', 'LinkedSource'):
                for r in refs:
                    s, p = rstr(b, p)
                    props.setdefault(r, {})[pname] = s
            elif typ == 0x02 and pname in ('Disabled', 'Archivable'):
                for r in refs:
                    props.setdefault(r, {})[pname] = b[p]; p += 1
        elif name == b'PRNT':
            n = u32(b, 1); p = 5
            kids, p = deinterleave_i32(b, p, n, True)
            pars, p = deinterleave_i32(b, p, n, True)
            for k, pr in zip(kids, pars): parent[k] = pr
    cls_of = {r: cn for cn, refs in classes.values() for r in refs}
    return cls_of, props, parent

def full_name(r, props, parent):
    parts = []
    while r != -1 and r in props or r in parent:
        parts.append(props.get(r, {}).get('Name', b'?').decode('utf-8', 'replace'))
        r = parent.get(r, -1)
        if r == -1: break
    return '.'.join(reversed(parts))

if __name__ == '__main__':
    path, outdir = sys.argv[1], sys.argv[2]
    os.makedirs(outdir, exist_ok=True)
    cls_of, props, parent = parse(path)
    def depth(r):
        d = 0
        while parent.get(r, -1) != -1: r = parent[r]; d += 1
        return d
    for r in sorted(cls_of, key=lambda r: (full_name(r, props, parent))):
        fn = full_name(r, props, parent)
        src = props.get(r, {}).get('Source')
        extra = ''
        if src is not None:
            nl = src.count(b"\n") + 1
            extra = f'  [{len(src)} bytes, {nl} lines]'
            fname = re.sub(r'[^\w.\-]', '_', fn) + '.' + cls_of[r] + '.luau'
            open(os.path.join(outdir, fname), 'wb').write(src)
        print('  ' * depth(r) + f'{props.get(r, {}).get("Name", b"?").decode("utf-8","replace")} ({cls_of[r]}){extra}')
