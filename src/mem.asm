; Shared memory map — boot, locode image, and segment tooling
; Default $01=$34 (I/O out). Disk loads use $36; chip touch uses $35.
; Krill loadraw needs $35 (IEC at $DD00) under SEI. Do not IOINIT while live.

BANK_RAM	= $34
BANK_LOADER	= $35			; I/O in, KERNAL out
BANK_IO		= $36			; I/O + KERNAL, BASIC out

; -DUSE_KRILL=1: native Krill (236 B at $4E00). Default 0: KERNAL LOAD ($FFD5).
!ifndef USE_KRILL {
	USE_KRILL = 0
}
; Reserved on both disks so BJH sprites cannot grow into the resident hole.
KRILL_HOLE	= $4E00			; loadraw on the Krill disk; unused otherwise
!if USE_KRILL {
	!source "../krill/loadersymbols-c64.inc"
	!if loadraw != KRILL_HOLE {
		!error "Krill loadraw is not KRILL_HOLE $4E00"
	}
}

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
; Boot splash (Koala split). splashc: matrix @ SCREEN, colour staged at SPLASH_COL.
; Overlaps SCREEN_B until scr loads; unused until then.
SPLASH_COL	= SCREEN + 1000		; $43E8
SPLASH_COL_SIZE	= 1000
SPLASH_BG	= SPLASH_COL + SPLASH_COL_SIZE	; $47D0
do_splash	= SPLASH_BG + 1		; $47D1 — helpers ride on splashc.prg tail
KOALA_COL_RAM	= $d800
KOALA_TAIL	= 1000 - 768		; 232
!if SPLASH_BG + 1 > BITMAP {
	!error "splash colour staging overlaps bitmap; bg=$", SPLASH_BG
}
SFX_BASE	= $3000			; pcsounds + pcsfreq_hi (CPU-only; locode–SQTAB gap)
BJH_SPRITES	= $4800			; 10 BJ-head HUD sprites (640 B, ptrs $20–$29)
; $4A80–$4DFF slack after BJH; $4E00–$4FFF reserved (Krill resident / unused)
WPN_SPRITES	= $5000			; HUD weapons + flashes (34 sprites → $5880)
MUX_HUD_RASTER	= 40			; face sprites (unexpanded) before HUD
MUX_WPN_RASTER	= 88			; restore weapon sprites after HUD 40px
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
; Item scratch + vis_depth/order live in RAM after end_paint (see wolf64.asm); must end ≤ ENEMY_BASE
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
; HUD dest cols; digit glyphs stay on bitmap rows 3–4 cols 0–9 (attrs 0)
UI_COL_LEVEL	= 2
UI_COL_SCORE	= 6			; 4 live digits + static 00
UI_COL_LIVES	= 14
UI_COL_FACE	= 19			; yellow silhouette (sprites overlay)
UI_COL_KEY_GOLD	= 17			; row 3 — attr on/off
UI_COL_KEY_SILVER = 22			; row 3 — attr on/off
UI_COL_HP	= 23
UI_COL_AMMO	= 29			; 2 digits (AMMO_MAX 99)
UI_ATTR_DIGIT	= $3e			; MCM cyan $3 + light blue $E
UI_COLR_DIGIT	= $00			; black
; UI_COLR_*_KEY live in ui_attr.inc (score overlay)
UI_BMP_ROW0	= BITMAP
UI_BMP_ROW1	= BITMAP + 1 * 320
UI_BMP_ROW3	= BITMAP + 3 * 320
SCORE_CODE	= BITMAP + 3 * 320 + 30 * 8	; row 3 cols 30–39 + row 4 cols 10–39 ($64B0)
SCORE_1UP	= 400			; extra life every 40,000 displayed
T_SECRET_ELEVATOR = 11			; Wolf wall 22; painted as T_ELEVATOR
T_ELEVATOR	= 13
T_PUSHWALL	= 14
T_EXIT		= 145
T_PUSH_TRAJ	= 146				; +0..3 = N,E,S,W
DEATH_MS	= 120			; frames≈; counted down with dt_ms sum ~2s feel
LEVEL_MAX	= 9			; 1..8 maps, 9 = boss (e1mb)
LEVEL_SECRET	= 10			; e1ms; HUD 10

; --- Button 2 / SID POTX ----------------------------------------------------
; The SID pot A/D is a free-running 512-cycle conversion and CIA1 PA6/PA7 (the
; top two bits of every $DC00 keyboard-row mask) drive the 4066 that feeds it.
; Any $DC00 write therefore invalidates the conversion in flight, so POTX may
; only be sampled after the mux has been parked on port 2 ($9F) for a couple of
; conversion periods. Shared by input.asm (game) and menu.asm (separate PRG).
BTN2_POT_LO	= $40			; raw < LO  -> button pressed (pot pulled low)
BTN2_POT_HI	= $c0			; raw >= HI -> released (line floats high)
					; LO..HI is the dead band: state is held
BTN2_DEB	= 2			; agreeing frames required to flip the latch
