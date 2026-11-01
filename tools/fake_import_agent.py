"""A stand-in for tools/import_agent.py in tests (TASK-28): follows the VTT <-> tool contract
(import-agent.md) without any AI. Writes progress.log, job.json and a small draft package with
a source page, then says done. Never prints or stores the API key, only whether it got one."""
import argparse, json, os, struct, sys, time, zlib


def png(path, w, h, rgb):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def main():
    ap = argparse.ArgumentParser()
    for a in ["--input", "--kind", "--target", "--job", "--packages"]:
        ap.add_argument(a, required=True)
    args = ap.parse_args()
    job = os.path.join(args.job, "job.json")
    state = json.load(open(job, encoding="utf-8"))
    log = open(os.path.join(args.job, "progress.log"), "a", encoding="utf-8")
    def say(text):
        log.write(text + "\n")
        log.flush()
    state["status"] = "running"
    json.dump(state, open(job, "w", encoding="utf-8"))
    say("Reading %s (%s)" % (os.path.basename(args.input), args.kind))
    say("API key: %s" % ("yes" if os.environ.get("ANTHROPIC_API_KEY") else "no"))
    say("Key in arguments: %s" % ("yes" if os.environ.get("ANTHROPIC_API_KEY") and any(os.environ["ANTHROPIC_API_KEY"] in a for a in sys.argv) else "no"))
    os.makedirs(os.path.join(args.job, "pages"), exist_ok=True)
    png(os.path.join(args.job, "pages", "1.png"), 200, 300, (200, 60, 40))
    origin = {"import": args.kind, "file": args.input, "page": 1}
    json.dump({"format": "dragoon-package", "format_version": 1, "id": state["id"], "name": "Import draft",
               "kind": "draft", "version": "0.0.0", "target": args.target}, open(os.path.join(args.job, "package.json"), "w"))
    monsters = [
        {"id": "bog-hag", "name": "Bog Hag", "type": "Fey", "cr": 3, "hp": 45, "ac": 14, "actions": ["bog-hag-claws"],
         "image": "", "description": "Lives in the mire.", "origin": origin, "source_page": "pages/1.png", "crop": [10, 20, 80, 90]},
        {"id": "ogre-cook", "name": "Ogre Cook", "type": "Giant", "cr": 2, "hp": 60, "ac": 11, "actions": [], "image": "",
         "description": "Imported cook.", "origin": origin, "source_page": "pages/1.png"},
        {"id": "ogre-cook-2", "name": "Ogre Cook", "type": "Giant", "cr": 2, "hp": 61, "ac": 11, "actions": [], "image": "",
         "description": "Second cook.", "origin": origin, "source_page": "pages/1.png"},
        {"id": "ogre-cook-3", "name": "Ogre Cook", "type": "Giant", "cr": 2, "hp": 62, "ac": 11, "actions": [], "image": "",
         "description": "Third cook.", "origin": origin, "source_page": "pages/1.png"},
    ]
    json.dump(monsters, open(os.path.join(args.job, "monsters.json"), "w"))
    json.dump([{"id": "bog-hag-claws", "name": "Claws", "text": "Melee Weapon Attack: +5 to hit.", "used_by": ["bog-hag"]}],
              open(os.path.join(args.job, "features.json"), "w"))
    time.sleep(0.3)
    say("4 drafts ready")
    state["status"] = "done"
    json.dump(state, open(job, "w", encoding="utf-8"))


if __name__ == "__main__":
    main()
