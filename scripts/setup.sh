#!/usr/bin/env bash
# Gera e compila o Resident Evil 2 Recompiled (Leon + Claire) a partir dos discos do proprio usuario.
# Uso: bash scripts/setup.sh "<CD1 Leon>.cue" "<CD2 Claire>.cue" [--sem-aot]
#   --sem-aot  pula a pre-compilacao dos trechos carregados do disco (instala mais
#              rapido, mas o jogo engasga um pouco na primeira vez que cada trecho aparece)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AOT=1
[[ "${3:-}" == "--sem-aot" ]] && AOT=0
if [[ $AOT -eq 1 ]]; then T=10; else T=8; fi

abs() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
LEON="${1:-}"; CLAIRE="${2:-}"
if [[ -z "$LEON" || ! -f "$LEON" || -z "$CLAIRE" || ! -f "$CLAIRE" ]]; then
    echo "erro: informe os arquivos .cue do CD1 (Leon) e do CD2 (Claire)." >&2
    echo "uso: bash scripts/setup.sh \"CD1 Leon.cue\" \"CD2 Claire.cue\" [--sem-aot]" >&2
    exit 1
fi
LEON="$(abs "$LEON")"; CLAIRE="$(abs "$CLAIRE")"

# python3 no Windows costuma ser um atalho da Microsoft Store que nao funciona.
PY=""
for c in python3 python py; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c "import sys; sys.exit(sys.version_info < (3, 9))" >/dev/null 2>&1; then
        PY="$c"; break
    fi
done
if [[ -z "$PY" ]]; then
    echo "erro: Python 3.9+ nao encontrado. Instale com: winget install Python.Python.3.12" >&2
    exit 1
fi

echo "== [1/$T] Baixando submodulos (psxrecomp + recomp-ui) =="
git submodule update --init --recursive

echo "== [2/$T] Preparando o compilador (baixa o toolchain Clang na primeira vez, ~209 MB) =="
TC_BIN="$("$PY" -c "
import sys; from pathlib import Path
sys.path.insert(0, 'psxrecomp/tools')
import toolchain_pack as tp
print(tp.ensure_toolchain(Path('.').resolve(), download=True, log=lambda m: print(m, file=sys.stderr)))
" | tail -n 1 | tr -d '\r')"
if [[ -z "$TC_BIN" ]]; then
    echo "erro: nao foi possivel preparar o toolchain." >&2
    exit 1
fi
TC_BIN="$(cygpath -u "$TC_BIN" 2>/dev/null || echo "$TC_BIN")"
export PSXRECOMP_TOOLCHAIN_DIR="$(dirname "$TC_BIN")"
export PATH="$TC_BIN:$PATH"
echo "toolchain: $PSXRECOMP_TOOLCHAIN_DIR"

echo "== [3/$T] Compilando o recompilador =="
bash psxrecomp/tools/ci/build_emitters.sh

# Os dois configs listam o conjunto inteiro de discos; cada programa monta so o seu.
"$PY" scripts/set_discs.py "$LEON" "$CLAIRE"

echo "== [4/$T] Gerando o codigo C do CD1 (Leon) =="
"$PY" psxrecomp/psxrecomp_cli.py generate --config game.toml --project-root . --disc "$LEON"

echo "== [5/$T] Gerando o codigo C do CD2 (Claire) =="
"$PY" psxrecomp/psxrecomp_cli.py generate --config claire.toml --project-root . --disc "$CLAIRE"

echo "== [6/$T] Compilando o Leon =="
"$PY" psxrecomp/psxrecomp_cli.py rebuild --config game.toml --project-root . \
    --build-dir build-release --no-pgo --cmake-extra=-DRE2_PROGRAM=leon

echo "== [7/$T] Compilando a Claire =="
"$PY" psxrecomp/psxrecomp_cli.py rebuild --config claire.toml --project-root . \
    --build-dir build-claire --no-pgo --cmake-extra=-DRE2_PROGRAM=claire

echo "== [8/$T] Juntando Leon e Claire na mesma pasta =="
cp -f build-claire/ResidentEvil2_Claire.exe build-release/
cp -f claire.toml build-release/ResidentEvil2_Claire.game.toml
for f in build-claire/ResidentEvil2_Claire.*; do
    [[ -f "$f" ]] && cp -f "$f" build-release/
done

if [[ $AOT -eq 1 ]]; then
    # O RE2 carrega trechos de codigo do disco durante o jogo. Pre-compila-los
    # agora evita os engasgos da primeira vez que cada trecho aparece.
    mkdir -p aot-work
    CLANG="$TC_BIN/clang.exe"
    [[ -f "$CLANG" ]] || CLANG="$TC_BIN/clang"
    # Cada compilacao usa ate ~700 MB de RAM: limita o paralelismo.
    JOBS="$(nproc 2>/dev/null || echo 4)"
    (( JOBS > 6 )) && JOBS=6
    n=9
    for prog in leon claire; do
        if [[ $prog == leon ]]; then CFG=game.toml; CUE="$LEON"; else CFG=claire.toml; CUE="$CLAIRE"; fi
        echo "== [$n/$T] Pre-compilando os trechos do disco ($prog) =="
        "$PY" psxrecomp/tools/aot_overlay_spike/extract_generic.py \
            --game-toml "$CFG" --recompiler build-recompiler/psxrecomp-game.exe \
            --disc "$CUE" --out "aot-work/$prog-records.json" --tmp "aot-work/extract-$prog"
        "$PY" psxrecomp/tools/compile_overlays.py \
            --captures "aot-work/$prog-records.json" --game-toml "$CFG" \
            --recompiler build-recompiler/psxrecomp-game.exe \
            --runtime-include psxrecomp/runtime/include \
            --out-dir build-release/cache --compiler gcc --gcc "$CLANG" \
            --flavor 0 --jobs "$JOBS"
        n=$((n + 1))
    done
fi

echo
echo "Pronto! Execute: build-release/ResidentEvil2_Leon.exe ou build-release/ResidentEvil2_Claire.exe"
