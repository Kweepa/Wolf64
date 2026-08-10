; Wolf64 — C64 textured ray walker (map 0)
; DDA: The Keep · multiply: Judd a²−b² · view: TechDesignDoc nibbles
!cpu 6502
!to "wolf64.prg", cbm

; --- build flags (SquareDoom-style) ---------------------------------------
PROFILE		= 1				; stage buckets on bitmap row 0
PROF_SPLIT	= 0				; 1 = per-col R/D (~80 CIA samples; +~20ms)
DBG_FPS		= 1				; F ≈ frame ms (cols 0–2)
MAX_HALF_H	= 75				; painter clamp (1..50 unrolled, 51..75 looped)

; --- memory map -----------------------------------------------------------
; $0801  BASIC stub + code + painter tables
; $4000  VIC screen A (bank 1)
; $4400  VIC screen B (double-buffer)
; $4800  textures (2K)
; $5000  map (4K)
; $6000  bitmap (8K, shared)
; $8000  compiled height painters
; $C800  Judd SQTAB (2K)

SCREEN		= $4000
SCREEN_B	= $4400
BITMAP		= $6000
TEXTURES	= $4800
MAP		= $5000
PAINTERS	= $8000
SQTAB1		= $C800
SQTAB2		= SQTAB1 + $200
SQTAB3		= SQTAB1 + $400
SQTAB4		= SQTAB1 + $600

; Spawn: map tiles 48..51 = player N,E,S,W (see find_spawn)

!source "zp.asm"

*= $0801
!byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00

*= $080d
start
	sei
	lda #$35
	sta $01					; stay here: VIC/CIA. $34 only inside render_frame

	lda #$ff
	sta $dc02
	lda #0
	sta $dc03

	jsr init_sqtabs
	jsr init_vic
	jsr prof_init
	jsr input_irq_init

	lda #$ff
	sta smc_last_page
	sta smc_last_h

	jsr find_spawn
	cli					; CIA1 Timer A key sampling

main_loop
	jsr calc_frame_dt
	jsr player_move
	jsr doors_update
	jsr render_frame
	jsr prof_frame_sample
	jsr prof_print
	jmp main_loop

!source "mul.asm"
!source "vic.asm"
!source "profil.asm"
!source "input.asm"
!source "dda.asm"
!source "doors.asm"
!source "render.asm"
!source "player.asm"
!source "tables.asm"
!source "painter_tables.asm"

col_texid
!fill 40, 0
col_half_h
!fill 40, 0
col_texx
!fill 40, 0

; Door anim slots (2)
door_x
!fill 2, 0
door_y
!fill 2, 0
door_pos
!fill 2, 0
door_state
!fill 2, 0
door_orient
!fill 2, 0
door_tic_l
!fill 2, 0
door_tic_h
!fill 2, 0
door_tile
!fill 2, 0
door_savex
!byte 0
door_savetl
!byte 0
door_saveth
!byte 0

turn_acc_l
!byte 0
turn_acc_h
!byte 0

; Profiler BSS (SquareDoom PROF_BSS layout, trimmed)
frame_t0
!fill 4, 0
frame_cy
!fill 4, 0
casc_now
!fill 4, 0
!if PROFILE = 1 {
casc_snap
!fill 4, 0
prof_dt
!fill 4, 0
prof_cy						; NBUCKET × 4-byte cycle totals
!fill PROF_NBUCKET * 4, 0
}

end_code = *
!if end_code > SCREEN {
	!error "Code overlaps SCREEN at $4000; end=$", end_code
}

*= TEXTURES
!binary "../textures/walls.bin", 2048

*= MAP
!binary "../maps/00_Wolf1_Map1.bin", 4096

*= PAINTERS
!binary "painters.bin"

end_painters = *
!if end_painters > $c800 {
	!error "Painters overlap SQTAB at $C800; end=$", end_painters
}
