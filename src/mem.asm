; Shared memory map — boot, locode image, and segment tooling
; Default $01=$34 (I/O out). Disk loads use $36; chip touch uses $35.
; Krill loadraw needs $35 (IEC at $DD00) under SEI. Do not IOINIT while live.
;
; VIC bank $8000–$BFFF ($dd00=%01). CPU owns $0900–$7FFF.

BANK_RAM	= $34
BANK_LOADER	= $35			; I/O in, KERNAL out
BANK_IO		= $36			; I/O + KERNAL, BASIC out

VIC_BANK_DD00	= %00000001		; VIC sees $8000–$BFFF

; -DUSE_KRILL=1: native Krill (236 B at $4E00). Default 0: KERNAL LOAD ($FFD5).
!ifndef USE_KRILL {
	USE_KRILL = 0
}
KRILL_HOLE	= $4E00			; loadraw on the Krill disk; reserved hole on both
!if USE_KRILL {
	!source "../krill/loadersymbols-c64.inc"
	!if loadraw != KRILL_HOLE {
		!error "Krill loadraw is not KRILL_HOLE $4E00"
	}
}

LOADER_BASE	= $0801			; disposable boot, then low BSS overlay
LOCODE_BASE	= $0900			; all game code (was locode + enemy*.asm)
REBOOT_STUB	= $08C0			; 3-byte JMP reboot_game
effects_vol	= $08FD
game_complete	= $08FE
difficulty	= $08FF

TABLES		= $0400

; --- VIC bank $8000 (same relative layout as old bank $4000) ---------------
SCREEN		= $8000			; matrix A
SCREEN_B	= $8400			; matrix B; sprite ptrs at SCREEN+$3F8
BITMAP		= $A000
BITMAP_SIZE	= 8000
BITMAP_END	= BITMAP + BITMAP_SIZE	; $BF40
BJH_SPRITES	= $8800			; 10 BJ-head HUD sprites (VIC-visible)
WPN_STAGE_SLOTS	= 12			; body + flash A/B (chaingun); ≤8 visible
WPN_MASTER	= $9000			; full WPN blob in char-ROM hole (CPU RAM)
; WPN_STAGE = 64-aligned after end_bjh (wolf64.asm); ITEM after end_wpn

; Boot splash (Koala). Matrix @ SCREEN; colour staged in SCREEN_B area until scr loads.
SPLASH_COL	= SCREEN + 1000		; $83E8
SPLASH_COL_SIZE	= 1000
SPLASH_BG	= SPLASH_COL + SPLASH_COL_SIZE	; $87D0
do_splash	= SPLASH_BG + 1		; $87D1
KOALA_COL_RAM	= $d800
KOALA_TAIL	= 1000 - 768
!if SPLASH_BG + 1 > BJH_SPRITES {
	!error "splash helpers overlap BJH_SPRITES; bg=$", SPLASH_BG
}

; --- Low CPU after code / Krill ------------------------------------------
; Code ≤ KRILL_HOLE; SFX at end_locode (label SFX_BASE in wolf64.asm).
; Paint + enemy pixels from PAINT_BASE; item gfx after WPN_MASTER (CPU).
PAINT_BASE	= $5000			; after Krill hole
MUX_HUD_RASTER	= 40
MUX_WPN_RASTER	= 88
MAX_VIS		= 48
MAX_ENEMIES	= 64

; --- High RAM ------------------------------------------------------------
; MAP @ $C000 (KERNAL SAVE-safe). TEX under KERNAL. SQTAB under I/O ($34).
; GAME_STATE = end_itm in wolf64.asm (pre-bitmap VIC pocket).
MAP		= $C000
MAP_SIZE	= 4096
MAP_END		= MAP + MAP_SIZE		; $D000
SQTAB1		= $D000			; 2K; disk loads at MAP then install_sqtabs
SQTAB2		= SQTAB1 + $200
SQTAB3		= SQTAB1 + $400
SQTAB4		= SQTAB1 + $600
ITM_SCRATCH	= $D800			; vis/item temps; $01=$34 only
TEX_LO		= $E000
TEX_HI		= $F000			; RAM-built rows 0..14; $FF00 is IRQ vector page
TEX_HI_R15	= $DF00			; row 15 shadow ($01=$34); avoids $FFFA–$FFFF
QS_STATE_SIZE	= 7 + 23 + 8 * 8 + 1 + 12 * MAX_ENEMIES	; 863

; Cassette / stack BSS
TAPE_BSS	= $033C
TAPE_BSS_END	= $03FC
STACK_BSS	= $0100
STACK_GUARD	= $01D0

; Pickup / HUD constants
AMMO_MAX	= 99
HP_MAX		= 100
AMMO_CLIP_AMT	= 8
FOOD_HP_AMT	= 10
DOGFOOD_HP_AMT	= 4
GUTS_HP_AMT	= 1
GUTS_HP_MAX	= 10
FIRSTAID_HP_AMT	= 25
ONEUP_AMMO_AMT	= 25
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
UI_COL_LEVEL	= 2
UI_COL_SCORE	= 6
UI_COL_LIVES	= 14
UI_COL_FACE	= 19
UI_COL_KEY_GOLD	= 17
UI_COL_KEY_SILVER = 22
UI_COL_HP	= 23
UI_COL_AMMO	= 29
UI_ATTR_DIGIT	= $3e
UI_COLR_DIGIT	= $00
UI_BMP_ROW0	= BITMAP
UI_BMP_ROW1	= BITMAP + 1 * 320
UI_BMP_ROW3	= BITMAP + 3 * 320
SCORE_CODE	= BITMAP + 3 * 320 + 30 * 8
SCORE_1UP	= 400
T_SECRET_ELEVATOR = 11
T_ELEVATOR	= 13
T_PUSHWALL	= 14
T_EXIT		= 145
T_PUSH_TRAJ	= 146
DEATH_MS	= 120
LEVEL_MAX	= 9
LEVEL_SECRET	= 10

; Quicksave — two KERNAL files: QS=GAME_STATE, QM=MAP
QS_VERSION	= 3
QS_HDR_LEN	= 7
QS_PLAYER_LEN	= 23
QS_DOOR_LEN	= 8 * 8
QS_ENEMY_SOA	= 12 * MAX_ENEMIES
QS_OFF_PLAYER	= QS_HDR_LEN
QS_OFF_DOORS	= QS_OFF_PLAYER + QS_PLAYER_LEN
QS_OFF_ECOUNT	= QS_OFF_DOORS + QS_DOOR_LEN
QS_OFF_ENEMY	= QS_OFF_ECOUNT + 1
QS_STATE_END	= QS_OFF_ENEMY + QS_ENEMY_SOA
!if QS_STATE_END != QS_STATE_SIZE {
	!error "QS_STATE_SIZE mismatch"
}

BTN2_POT_LO	= $40
BTN2_POT_HI	= $c0
BTN2_DEB	= 2
