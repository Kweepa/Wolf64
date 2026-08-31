#!/bin/bash
set -e

# Unix counterpart to build.bat — keep the two in step.
# Builds both disks: wolf64-krill.d64 (Krill loadraw, needs TDE / real 1541)
# and wolf64.d64 (KERNAL loader).

mkdir -p generated

python3 tools/gensounds.py
python3 tools/gentables.py
python3 tools/gen_sqtab.py
python3 tools/gen_bss.py
python3 tools/gen_menufont.py
python3 tools/gen_menu_logo.py
python3 tools/gen_menu_hint_sprites.py
python3 tools/gen_menu_cursor_sprites.py
python3 tools/gen_menu_text.py
python3 tools/gen_painters.py
python3 tools/extract_walls.py --from-preview
python3 tools/pack_enemies.py
python3 tools/pack_items.py
python3 tools/gen_weapon_sprites.py
python3 tools/gen_enemy_painters.py
python3 tools/gen_ui_bitmap.py
python3 tools/gen_splash.py

cd src
acme -v3 menu.asm

# Krill disk first (236-byte loadraw @ $4E00 — SFX must end before $4E00)
acme -DUSE_KRILL=1 -v3 --vicelabels ../generated/wolf64-krill.lbl wolf64.asm
acme -DUSE_KRILL=1 -v3 splashc.asm
acme -DUSE_KRILL=1 boot.asm
cd ..

python3 tools/mkdisk.py --all-maps --krill --out wolf64-krill.d64 --labels generated/wolf64-krill.lbl

cd src
acme -v3 --vicelabels ../generated/wolf64.lbl wolf64.asm
acme -v3 splashc.asm
acme -v3 boot.asm
cd ..

python3 tools/mkdisk.py --all-maps

echo "Built wolf64.d64 (KERNAL) and wolf64-krill.d64"
ls -l wolf64.d64 wolf64-krill.d64
