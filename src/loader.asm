; Disk load helpers — resident in locode (map load + restart).
; Same KERNAL sequence as boot: SETNAM / SETLFS / LOAD / CLOSE.
; Caller pages KERNAL in and IOINITs before first load if needed.
;
; Screen blanked (DEN=0, black border/bg, sprites off) during LoadLevel.
!zone loader

LEVEL_DEVICE	= 8

level_dos_name
	!text "E1M1"

; FormatDosName — "ENMM" from episode (0→E1) + level_num (1→M1, 9→MB)
FormatDosName
	lda #'E'
	sta level_dos_name
	lda episode
	clc
	adc #'1'
	sta level_dos_name + 1
	lda #'M'
	sta level_dos_name + 2
	lda level_num
	cmp #9
	bne .fdn_digit
	lda #'B'
	sta level_dos_name + 3
	rts
.fdn_digit
	clc
	adc #'0'
	sta level_dos_name + 3
	rts

; LoadPrg — A=name length, X/Y=name pointer. KERNAL must already be paged in.
; C=0 ok, C=1 error. Caller sets $d020 before calling.
LoadPrg
	sta load_namelen
	stx load_name_l
	sty load_name_h

	lda load_namelen
	ldx load_name_l
	ldy load_name_h
	jsr $ffbd				; SETNAM
	lda #1
	ldx #LEVEL_DEVICE
	ldy #1					; SA=1 → PRG load address
	jsr $ffba				; SETLFS
	lda #0
	jsr $ffd5				; LOAD
	php
	pha
	lda #1
	jsr $ffc3				; CLOSE
	pla
	plp
	rts

; Blank VIC — DEN off, black border/bg, no sprites (I/O must be in).
blank_screen
	lda #0
	sta $d015
	sta $d020
	sta $d021
	lda $d011
	and #%11101111
	sta $d011
	rts

; LoadLevel — disable game CIA IRQ, IOINIT, blank, LoadPrg.
; C=0 ok, C=1 error. Caller must re-init IRQs/ZP (see restart_level).
LoadLevel
	sei
	lda #$35
	sta $01
	lda #$7f
	sta $dc0d				; kill game Timer A IRQ before KERNAL
	lda $dc0d
	lda #$36
	sta $01
	jsr $ff84				; IOINIT
	lda #$35
	sta $01
	jsr blank_screen
	lda #$36
	sta $01
	cli
	jsr FormatDosName
	lda #4
	ldx #<level_dos_name
	ldy #>level_dos_name
	jmp LoadPrg

; restart_level — reload current episode/level map and re-init actors
; Preserves owned_weapons / ammo / score / lives (caller sets HP/keys as needed).
; LoadLevel IOINITs + KERNAL LOAD clobber ZP/CIA — recover like game_start.
restart_level
	jsr LoadLevel
	bcs .rl_fail

	sei
	lda #$35
	sta $01
	lda #$ff
	sta $dc02
	lda #0
	sta $dc03
	jsr init_sqtabs
	jsr init_vic
	jsr prof_init
	jsr input_irq_init
	jsr play_sound_init
	lda #$ff
	sta smc_last_page
	sta smc_last_h

	jsr doors_clear
	jsr find_spawn
	lda #$34
	sta $01					; map + enemy RAM visible
	jsr enemies_init
	jsr items_init
	lda #$35
	sta $01
	jsr refresh_weapon
	clc
.rl_fail
	rts
