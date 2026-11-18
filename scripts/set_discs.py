"""Grava os caminhos dos dois discos em game.toml (Leon) e claire.toml (Claire).

O psxrecomp trata o RE2 como um conjunto com um programa por disco: os dois
configs listam o conjunto inteiro em [game] discs / disc_serials, e
program_discs diz qual disco cada programa inicia (docs/config_schema.md,
"Several programs in one set"). So as linhas dessas chaves sao reescritas;
o resto do arquivo fica como esta.

Tambem registra em [prepare_disc] os digests da imagem do proprio usuario: o
dump pode ser o original em ingles ou ter o patch de dublagem (que tem mais de
uma versao), e o generate do psxrecomp so aceita imagens listadas ali.

Uso: python scripts/set_discs.py "<CD1 Leon>.cue" "<CD2 Claire>.cue"
"""
import hashlib
import re
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SERIALS = ["SLUS-00748", "SLUS-00756"]
KEYS = ("disc", "discs", "disc_serials", "program_discs")


def q(path: str) -> str:
    return '"' + path.replace("\\", "/").replace('"', '\\"') + '"'


def update(cfg: Path, discs: list, own: int) -> None:
    lines = cfg.read_text(encoding="utf-8").splitlines()
    out, in_game, skip_array = [], False, False
    for ln in lines:
        s = ln.strip()
        if skip_array:
            if s.endswith("]"):
                skip_array = False
            continue
        if s.startswith("["):
            in_game = s == "[game]"
        key = re.match(r"([A-Za-z_]+)\s*=", s)
        if in_game and key and key.group(1) in KEYS:
            if key.group(1) == "disc":
                out.append(f"disc = {q(discs[own - 1])}")
                out.append("discs = [" + ", ".join(q(d) for d in discs) + "]")
                out.append("disc_serials = [" + ", ".join(f'"{x}"' for x in SERIALS) + "]")
                out.append(f"program_discs = [{own}]")
            if "[" in s.split("=", 1)[1] and not s.endswith("]"):
                skip_array = True
            continue
        out.append(ln)
    cfg.write_text("\n".join(out) + "\n", encoding="utf-8")


def data_track(cue: Path) -> Path:
    """Primeiro .bin citado no .cue (a trilha de dados)."""
    for ln in cue.read_text(encoding="latin-1").splitlines():
        m = re.match(r'\s*FILE\s+"([^"]+)"', ln) or re.match(r"\s*FILE\s+(\S+)", ln)
        if m:
            return cue.parent / m.group(1)
    return cue.with_suffix(".bin")


def digests(binf: Path) -> dict:
    md5, sha1, crc = hashlib.md5(), hashlib.sha1(), 0
    with open(binf, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            md5.update(chunk)
            sha1.update(chunk)
            crc = zlib.crc32(chunk, crc)
    return {"known_sizes": str(binf.stat().st_size), "known_md5": md5.hexdigest(),
            "known_sha1": sha1.hexdigest(), "known_crc32": f"{crc & 0xFFFFFFFF:08x}"}


def add_digests(cfg: Path, d: dict) -> None:
    lines = cfg.read_text(encoding="utf-8").splitlines()
    for key, val in d.items():
        item = val if key == "known_sizes" else f'"{val}"'
        for i, ln in enumerate(lines):
            if not ln.strip().startswith(f"{key} = ["):
                continue
            block = [ln]
            if not ln.rstrip().endswith("]"):
                for x in lines[i + 1:]:
                    block.append(x)
                    if x.strip().startswith("]"):
                        break
            if any(item in x for x in block):
                break
            if ln.rstrip().endswith("]"):          # lista numa linha so
                body = ln.rstrip()[:-1].split("[", 1)[1].strip().rstrip(",")
                lines[i] = f"{key} = [{body + ', ' if body else ''}{item}]"
            else:                                   # lista em varias linhas
                lines.insert(i + 1, f"  {item},")
            break
    cfg.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    discs = [str(Path(p).resolve()) for p in sys.argv[1:3]]
    for p in discs:
        if not Path(p).is_file():
            print(f"erro: arquivo nao encontrado: {p}", file=sys.stderr)
            return 1
    update(ROOT / "game.toml", discs, 1)
    update(ROOT / "claire.toml", discs, 2)
    for cfg, cue in ((ROOT / "game.toml", discs[0]), (ROOT / "claire.toml", discs[1])):
        binf = data_track(Path(cue))
        if not binf.is_file():
            print(f"erro: o .cue aponta para um .bin que nao existe: {binf}", file=sys.stderr)
            return 1
        print(f"conferindo {binf.name}...")
        add_digests(cfg, digests(binf))
    print("discos gravados em game.toml e claire.toml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
