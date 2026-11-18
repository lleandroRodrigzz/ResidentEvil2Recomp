cmake_minimum_required(VERSION 3.20)
set(PSXRECOMP_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/psxrecomp" CACHE PATH
    "Path to psxrecomp")
if(NOT EXISTS "${PSXRECOMP_ROOT}/runtime/runtime.cmake")
    message(FATAL_ERROR
        "PSXRecomp runtime is missing: ${PSXRECOMP_ROOT}/runtime/runtime.cmake\n"
        "This project expects the psxrecomp framework checkout at ${PSXRECOMP_ROOT}.\n"
        "Run: git submodule update --init --recursive\n"
        "If psxrecomp/ is not a submodule, set -DPSXRECOMP_ROOT=<path-to-psxrecomp>.")
endif()

project(ResidentEvil2Recomp LANGUAGES C CXX)

# --- Opt-in product surfaces (OFF by default in the framework) -------------
# Scaffold prompts / flags fill these. Without recomp-ui, PSX_RECOMP_UI is OFF.
# The wizard (WIZARD_CMAKE_BLOCK / ENABLE_SETUP_WIZARD) is the first-run disc
# picker; releases are compiled from the committed generated/ C, so it never
# needs to generate or rebuild anything on a player's machine.
# recomp-ui submodule present (PSX_RECOMP_UI defaults ON).
# Full netplay UI — enable after adding recomp-ui + testing:
# if(EXISTS "${PSXRECOMP_ROOT}/lib/recomp-net/CMakeLists.txt")
#     set(PSX_NETPLAY ON CACHE BOOL "…" FORCE)
# endif()
set(PSX_SETUP_WIZARD ON CACHE BOOL
    "Advertise first-run setup wizard + Generate & rebuild in recomp-ui" FORCE)
include("${PSXRECOMP_ROOT}/runtime/runtime.cmake")

# This project's own mod catalog. The FRAMEWORK stages it -- together with its
# builtin psx.* packages -- into <exe-dir>/mods/bundled, and refuses to
# configure if a catalog exists here but is not declared. Shared Internal
# Resolution is included even with a builtin allowlist, enabled at 4x on fresh
# profiles, with 1x..32x choices; do not supply a title-local copy of that id.
# Never copy the catalog by hand: five titles did, and framework 4cc04be3's rename of the staged
# directory broke all five silently (bead beads-eio.3.101).
set(PSX_PRELOADED_MODS "${CMAKE_CURRENT_SOURCE_DIR}/mods/preloaded")
if(NOT IS_DIRECTORY "${PSX_PRELOADED_MODS}")
    set(PSX_PRELOADED_MODS "NONE")
endif()

# Resident Evil 2 tem um programa por disco (Leon no CD1, Claire no CD2).
# Cada um e um build separado: -DRE2_PROGRAM=leon (padrao) ou claire.
set(RE2_PROGRAM "leon" CACHE STRING "Programa do RE2 a compilar: leon ou claire")
if(RE2_PROGRAM STREQUAL "claire")
    set(RE2_BOOT "SLUS_007.56")
    set(RE2_GEN_DIR "generated_claire")
    set(RE2_EXE "ResidentEvil2_Claire")
    set(RE2_TITLE "Resident Evil 2 - Claire")
    set(RE2_CONFIG "claire.toml")
    add_compile_definitions(RE2_CLAIRE=1)
elseif(RE2_PROGRAM STREQUAL "leon")
    set(RE2_BOOT "SLUS_007.48")
    set(RE2_GEN_DIR "generated")
    set(RE2_EXE "ResidentEvil2_Leon")
    set(RE2_TITLE "Resident Evil 2 - Leon")
    set(RE2_CONFIG "game.toml")
else()
    message(FATAL_ERROR "RE2_PROGRAM deve ser leon ou claire (recebido: ${RE2_PROGRAM})")
endif()

psxrecomp_add_game_runtime(psx-runtime
    PRELOADED_MODS_DIR "${PSX_PRELOADED_MODS}"
    # ENABLE_NETPLAY_IF_PRESENT
    # NETPLAY_LOBBY_URL "ws://netplay.retcomm.net:8765"
    ENABLE_SETUP_WIZARD
    WINDOW_TITLE "${RE2_TITLE}"
    EXE_NAME "${RE2_EXE}"
    DEFAULT_GAME_CONFIG_PATH "game.toml"
    MAX_PLAYERS 1
    # LAUNCHER_BOXART "${CMAKE_CURRENT_SOURCE_DIR}/launcher_assets/img/boxart.tga"
    APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/assets/psxrecomp.ico"
    # Committed game C (psxrecomp_cli.py generate; git add generated). Release
    # CI configures with -DPSXRECOMP_REQUIRE_GAME_C=ON so a checkout without
    # it fails instead of building a setup host.
    GEN_MARKER "${RE2_GEN_DIR}/${RE2_BOOT}_dispatch.c"
    GEN_FULL_GLOB "${RE2_GEN_DIR}/${RE2_BOOT}_full_*.c"
    CODEGEN_SETUP_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/codegen_setup.c"
)

# Stage runtime configs next to the exe for direct build/ launches. Each exe
# reads "<exe name>.game.toml" beside it first, so the Leon and Claire exes can
# share one folder (settings, key binds and saves) with their own configs.
add_custom_command(TARGET psx-runtime POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/${RE2_CONFIG}"
        "$<TARGET_FILE_DIR:psx-runtime>/${RE2_EXE}.game.toml"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/${RE2_CONFIG}"
        "$<TARGET_FILE_DIR:psx-runtime>/game.toml"
    COMMENT "Staging ${RE2_CONFIG}"
    VERBATIM)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/game_options.toml")
    add_custom_command(TARGET psx-runtime POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_CURRENT_SOURCE_DIR}/game_options.toml"
            "$<TARGET_FILE_DIR:psx-runtime>/game_options.toml"
        VERBATIM)
endif()
