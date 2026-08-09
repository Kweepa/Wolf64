; Wolf64 — C64 textured ray walker (map 0)
; DDA: The Keep · multiply: Judd a²−b² · view: TechDesignDoc nibbles
!cpu 6502
!to "wolf64.prg", cbm

; --- memory map -----------------------------------------------------------
; $0801  BASIC stub + code
; $3000  Judd SQTAB (2K)
; $4000  VIC screen (bank 1)
; $4800  textures (2K)
; $5000  map (4K)
; $6000  bitmap (8K)
; $E000  transposed frame buffer (40×24)

SCREEN		= $4000
BITMAP		= $6000
TEXTURES	= $4800
MAP		= $5000
FRAMEBUF	= $E000
; Judd tables in always-RAM under KERNAL scrap (built at runtime)
SQTAB1		= $C800
SQTAB2		= SQTAB1 + $200
SQTAB3		= SQTAB1 + $400
SQTAB4		= SQTAB1 + $600

; Spawn: E1M1 player at (29,57) facing East
SPAWN_X		= 29
SPAWN_Y		= 57
SPAWN_A		= 0				; east

!source "zp.asm"

; BASIC stub SYS 2061
*= $0801
!byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00

*= $080d
start
	sei
	lda #$35
	sta $01					; I/O in, ROMs out

	jsr init_sqtabs
	jsr init_vic

	lda #$80				; center of tile (stable DDA fracs)
	sta playerx_l
	sta playery_l
	lda #SPAWN_X
	sta playerx_h
	lda #SPAWN_Y
	sta playery_h
	lda #SPAWN_A
	sta playera

main_loop
	jsr render_frame
	jsr player_move
	jmp main_loop

!source "mul.asm"
!source "vic.asm"
!source "dda.asm"
!source "render.asm"
!source "player.asm"
!source "tables.asm"

; Per-column hit texture id (0 = sky/miss) for top-row debug
col_texid
!fill 40, 0

end_code = *
!if end_code > SCREEN {
	!error "Code overlaps SCREEN at $4000; end=$", end_code
}

; --- assets ---------------------------------------------------------------
*= TEXTURES
!binary "../textures/walls.bin", 2048

*= MAP
!binary "../maps/00_Wolf1_Map1.bin", 4096
