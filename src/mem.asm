; Shared memory map — boot, locode image, and segment tooling
; Default $01=$34 (I/O out). Disk loads use $36; chip touch uses $35.

LOADER_BASE	= $0801			; disposable boot, then low BSS overlay
LOCODE_BASE	= $0900			; resident low code (locode.prg); also MENU overlay pre-load
; future: HICODE — separate disk PRG for overflow / under-ROM code
; Survives after boot: reboot stub + menu-owned selectors (BSS ends ≤ REBOOT_STUB)
REBOOT_STUB	= $08C0			; 3-byte JMP reboot_game (enemy); game over → menu
effects_vol	= $08FD			; menu SFX level 0..15 → SID $d418
game_complete	= $08FE			; 1 = show endings on next menu entry
difficulty	= $08FF			; menu skill 0..3 (not ZP; trampoline leaves alone)

TABLES		= $0400			; tables.asm (free bank-0 screen RAM)
SCREEN		= $4000			; video matrix A (1000 bytes)
SCREEN_B	= $4400			; matrix B; $43E8–$43FF = sprite ptrs (SCR pads 24B)
BITMAP		= $6000
BITMAP_SIZE	= 8000			; VIC bitmap (last 192 of 8K unused)
BITMAP_END	= BITMAP + BITMAP_SIZE	; $7F40
SFX_BASE	= $4800			; pcsounds + pcsfreq_hi (old TEXTURES slot; walls.bin retired)
WPN_SPRITES	= $5000			; HUD weapons + flashes (34 sprites → $5880)
ITEM_SPRITES	= $5880			; world item gfx (4bpp + LUTs; to bitmap $6000)
MAX_VIS		= 48			; enemies + items in one depth-sorted draw list
MAX_ENEMIES	= 64			; enemy SoA pool (hot in enemy PRG / gap / stack)
SQTAB1		= $3800			; Judd 2K (disk: sqt; locode..screen gap)
SQTAB2		= SQTAB1 + $200
SQTAB3		= SQTAB1 + $400
SQTAB4		= SQTAB1 + $600
TEX_LO		= $8000			; 16 rows x 256 (texx*16+id); disk-loaded (tex_lo.bin)
; TEX_HI is NOT disk-loaded: init_tex_hi (render.asm) builds it once at boot
; by shifting each TEX_LO byte left 4 bits into this RAM-only block. Fixed
; address (not PAINTERS + painters.asm's compiled size) so painters.asm can
; grow or shrink without moving TEX_HI.
TEX_HI		= TEX_LO + 4096
PAINTERS	= TEX_HI + 4096
; Item scratch + vis_depth/order live in RAM after end_sfx (see wolf64.asm); must end ≤ ENEMY_BASE
; col_enemy is 40 bytes at end_itm (itm→bitmap slack)
ENEMY_BASE	= $C000			; contiguous enemy code+gfx+hot SoA
MAP		= $EF00			; 4K level (under-KERNAL; LoadLevel)
; Cassette buffer — locode runtime BSS (disk LOAD does not use tape buf)
TAPE_BSS	= $033C
TAPE_BSS_END	= $03FC			; exclusive; 192 bytes
; Page-1 BSS under the hardware stack. SP must stay ≥ STACK_GUARD.
STACK_BSS	= $0100
STACK_GUARD	= $01D0			; 48 bytes for IRQ + nested jsr ($01D0–$01FF)

; Pickup / HUD constants
AMMO_MAX	= 99
HP_MAX		= 100
AMMO_CLIP_AMT	= 8
FOOD_HP_AMT	= 10
DOGFOOD_HP_AMT	= 4
GUTS_HP_AMT	= 1
GUTS_HP_MAX	= 10			; only if HP <= 10%
FIRSTAID_HP_AMT	= 25
ONEUP_AMMO_AMT	= 25			; Wolf GiveAmmo(25) with extra life
START_AMMO	= 8
START_LIVES	= 3
LIVES_MAX	= 9
KEY_GOLD	= $01
KEY_SILVER	= $02
UI_DIRTY_HP	= $01
UI_DIRTY_AMMO	= $02
UI_DIRTY_LEVEL	= $04
UI_DIRTY_LIVES	= $08
UI_DIRTY_FACE	= $10
UI_DIRTY_KEYS	= $20
UI_DIRTY_SCORE	= $40
UI_DIRTY_ALL	= $7F
; HUD dest cols; digits flattened on bitmap row 3; faces hidden at cols 32–39 rows 0–2
UI_COL_LEVEL	= 2
UI_COL_SCORE	= 6			; 4 live digits + static 00
UI_COL_LIVES	= 14
UI_COL_FACE	= 19			; live face dest (2×3 cells, rows 0–2)
UI_COL_KEY_GOLD	= 18			; row 2 — attr on/off
UI_COL_KEY_SILVER = 21			; row 2 — attr on/off
UI_COL_HP	= 23
UI_COL_AMMO	= 29			; 2 digits (AMMO_MAX 99)
UI_FACE_COL0	= 32			; bank: face f at col 32+f*2, rows 0–2
UI_N_FACES	= 4
UI_ATTR_DIGIT	= SCREEN + 3 * 40 + 20	; digit 0..9 screen attrs
UI_COLR_DIGIT	= $d800 + 3 * 40 + 20
; UI_ATTR_FACE / UI_COLR_*_KEY live in ui_attr.inc (score overlay)
UI_BMP_ROW0	= BITMAP
UI_BMP_ROW1	= BITMAP + 1 * 320
UI_BMP_ROW3	= BITMAP + 3 * 320
SCORE_CODE	= BITMAP + 3 * 320 + 30 * 8	; row 3 cols 30–39 + row 4 ($64B0)
SCORE_1UP	= 400			; extra life every 40,000 displayed
T_SECRET_ELEVATOR = 11			; Wolf wall 22; painted as T_ELEVATOR
T_ELEVATOR	= 13
T_PUSHWALL	= 14
T_EXIT		= 145
T_PUSH_TRAJ	= 146				; +0..3 = N,E,S,W
DEATH_MS	= 120			; frames≈; counted down with dt_ms sum ~2s feel
LEVEL_MAX	= 9			; 1..8 maps, 9 = boss (e1mb)
LEVEL_SECRET	= 10			; e1ms; HUD 10
