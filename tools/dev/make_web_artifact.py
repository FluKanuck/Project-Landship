"""
Package build/web for hosting where single files must stay small: split index.wasm and
index.pck into parts and add a fetch shim to index.html that stitches them back together.

    python3 tools/dev/make_web_artifact.py build/web build/web_split
"""
import os
import shutil
import sys

CHUNK = 12 * 1024 * 1024

SHIM = """<script>
(function () {
  const PARTS = %s;
  const realFetch = window.fetch.bind(window);
  window.fetch = async function (input, init) {
    const url = (typeof input === 'string') ? input : (input && input.url) || '';
    const path = url.split('?')[0];
    for (const name in PARTS) {
      if (path.endsWith(name)) {
        const bufs = [];
        let total = 0;
        for (let i = 0; i < PARTS[name]; i++) {
          const r = await realFetch(name + '.part' + i + '.bin');
          if (!r.ok) throw new Error('missing ' + name + ' part ' + i);
          const b = new Uint8Array(await r.arrayBuffer());
          bufs.push(b);
          total += b.length;
        }
        const out = new Uint8Array(total);
        let o = 0;
        for (const b of bufs) { out.set(b, o); o += b.length; }
        return new Response(out, { status: 200, headers: {
          'Content-Type': name.endsWith('.wasm') ? 'application/wasm' : 'application/octet-stream',
          'Content-Length': String(total) } });
      }
    }
    return realFetch(input, init);
  };
})();
</script>
"""


def main(src, dst):
    if os.path.exists(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    parts = {}
    for name in os.listdir(src):
        p = os.path.join(src, name)
        if name in ("index.wasm", "index.pck"):
            data = open(p, "rb").read()
            n = 0
            for i in range(0, len(data), CHUNK):
                with open(os.path.join(dst, f"{name}.part{n}.bin"), "wb") as f:
                    f.write(data[i:i + CHUNK])
                n += 1
            parts[name] = n
        else:
            shutil.copy(p, os.path.join(dst, name))
    html = open(os.path.join(dst, "index.html")).read()
    import json
    html = html.replace("<head>", "<head>\n" + SHIM % json.dumps(parts), 1)
    html = html.replace("<title>", "<title>", 1)
    open(os.path.join(dst, "index.html"), "w").write(html)
    print("parts:", parts)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
