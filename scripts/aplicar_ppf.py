"""Aplica um patch PPF (versoes 1.0, 2.0 e 3.0) numa copia da imagem do disco.

A imagem original nunca e alterada: o resultado vai para um arquivo novo, e
um .cue com o mesmo nome e criado ao lado dele.
Uso: python scripts/aplicar_ppf.py "<original>.bin" "<patch>.ppf" "<saida>.bin"
"""
import shutil
import sys
from pathlib import Path

DIZ_BEGIN = b"@BEGIN_FILE_ID.DIZ"


def fail(msg: str) -> None:
    print(f"erro: {msg}", file=sys.stderr)
    sys.exit(1)


def records_end(data: bytes, version: int) -> int:
    """Fim da area de registros, descontando o FILE_ID.DIZ opcional no final."""
    pos = data.rfind(DIZ_BEGIN)
    if pos < 0 or version == 1:
        return len(data)
    return pos


def apply(image: Path, patch: Path, out: Path) -> None:
    data = patch.read_bytes()
    magic = data[:5]
    if magic not in (b"PPF10", b"PPF20", b"PPF30"):
        fail(f"{patch.name} nao e um patch PPF")
    version = int(chr(magic[3]))
    desc = data[6:56].decode("latin-1").strip()
    print(f"patch PPF {version}.0: {desc or '(sem descricao)'}")

    if out.resolve() == image.resolve():
        fail("o arquivo de saida precisa ser diferente da imagem original")

    # Confere a imagem antes de copiar qualquer coisa.
    def block_at(offset: int) -> bytes:
        with open(image, "rb") as f:
            f.seek(offset)
            return f.read(1024)

    if version == 1:
        pos, undo, offsize = 56, False, 4
    elif version == 2:
        size = int.from_bytes(data[56:60], "little")
        if size != image.stat().st_size:
            fail(f"o patch espera uma imagem de {size:,} bytes; a sua tem {image.stat().st_size:,}")
        if block_at(0x9320) != data[60:1084]:
            fail("a imagem nao e a versao que o patch espera")
        pos, undo, offsize = 1084, False, 4
    else:
        imagetype, blockcheck, undo = data[56], data[57], bool(data[58])
        pos = 60
        if blockcheck:
            if block_at(0x80A0 if imagetype == 1 else 0x9320) != data[60:1084]:
                fail("a imagem nao e a versao que o patch espera "
                     "(confira se e o dump correto do disco)")
            pos = 1084
        offsize = 8

    shutil.copyfile(image, out)
    with open(out, "r+b") as img:
        end = records_end(data, version)
        count = 0
        while pos < end:
            if pos + offsize + 1 > end:
                break
            offset = int.from_bytes(data[pos:pos + offsize], "little")
            n = data[pos + offsize]
            pos += offsize + 1
            img.seek(offset)
            img.write(data[pos:pos + n])
            pos += n * (2 if undo else 1)
            count += 1
    print(f"{count:,} trechos aplicados -> {out}")
    write_cue(image, out)


def write_cue(image: Path, out: Path) -> None:
    """Cria <saida>.cue: copia o .cue da imagem original trocando o nome do .bin."""
    cue_out = out.with_suffix(".cue")
    if cue_out.exists():
        print(f"{cue_out.name} ja existe; nao foi alterado")
        return
    cue_in = image.with_suffix(".cue")
    if cue_in.is_file():
        lines = []
        for ln in cue_in.read_text(encoding="latin-1").splitlines():
            if ln.strip().upper().startswith("FILE"):
                ln = f'FILE "{out.name}" BINARY'
            lines.append(ln)
    else:
        lines = [f'FILE "{out.name}" BINARY', "  TRACK 01 MODE2/2352", "    INDEX 01 00:00:00"]
    # newline="\r\n": .cue no padrao Windows/Redump
    with open(cue_out, "w", encoding="latin-1", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"criado {cue_out.name}")


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 1
    image, patch, out = (Path(a) for a in sys.argv[1:4])
    for p in (image, patch):
        if not p.is_file():
            fail(f"arquivo nao encontrado: {p}")
    apply(image, patch, out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
