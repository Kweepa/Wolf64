; Disk load helpers — resident in locode (map load + restart).
; USE_KRILL=1: loadraw, no IOINIT. Default: KERNAL SETNAM/SETLFS/LOAD/CLOSE.
;
; Screen blacked during LoadLevel (DEN off until first swap_view).
!zone loader

level_dos_name
	!text "E1M1"
	!byte 0

; FormatDosName — "ENMM" from episode (0→E1) + level_num (1→M1, 9→MB, 10→MS)
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
	cmp #LEVEL_SECRET
	bne .fdn_boss
	lda #'S'
	sta level_dos_name + 3
	rts
.fdn_boss
	cmp #LEVEL_MAX
	bne .fdn_digit
	lda #'B'
	sta level_dos_name + 3
	rts
.fdn_digit
	clc
	adc #'0'
	sta level_dos_name + 3
	rts

; Black border/bg, sprites off, DEN off. Border still shows if load fails
; (init_vic leaves DEN off; caller sets $d020).
blank_screen
	lda #$2b				; absolute — RMW writes the live raster MSB into RST8
	sta $d011
	lda #0
	sta $d015
	sta $d01a
	sta $d020
	sta $d021
	lda $d019
	sta $d019
	rts

!if USE_KRILL {

; LoadPrg — X/Y = 0-terminated name. Dest from PRG header (carry clear).
; C=0 ok, C=1 error. Do not IOINIT: $DD02=$3F uninstalls Krill drive code.
LoadPrg
	stx load_name_l
	sty load_name_h

	sei
	cld
	lda #BANK_LOADER
	sta $01
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #0
	sta $d01a
	sta $dd0e
	sta $dd0f

	ldx load_name_l
	ldy load_name_h
	clc					; dest from PRG header
	jsr loadraw
	php

	lda #BANK_LOADER
	sta $01
	lda #%00000010
	sta $dd00
	plp
	rts

; LoadLevel — blank + loadraw. Never IOINIT (kills drive code).
; C=0 ok, C=1 error. Caller must re-init IRQs/ZP (see restart_level).
LoadLevel
	sei
	lda #BANK_LOADER
	sta $01
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #0
	sta $d01a
	lda $d019
	sta $d019
	jsr blank_screen
	jsr FormatDosName
	ldx #<level_dos_name
	ldy #>level_dos_name
	jmp LoadPrg

} else {

; LoadPrg — A=name length, X/Y=name pointer. KERNAL must already be paged in.
; C=0 ok, C=1 error.
LoadPrg
	sta load_namelen
	stx load_name_l
	sty load_name_h

	lda load_namelen
	ldx load_name_l
	ldy load_name_h
	jsr $ffbd				; SETNAM
	lda #1
	ldx $ba					; same device as boot load
	ldy #1					; SA=1 → PRG load address
	jsr $ffba				; SETLFS
	lda #0
	jsr $ffd5				; LOAD (A must be 0)
	php
	pha
	lda #1
	jsr $ffc3				; CLOSE
	pla
	plp
	rts

; IOINIT can leave CIA2 Timer A generating NMIs. Mask the NMI without
; stopping the timers — $dd0e/$dd0f=0 plus DEN=0 stalls KERNAL IEC.
load_cia2_nmi_off
	lda #0
	sta $02a1				; KERNAL CIA2 ICR shadow; prevent FE88 re-enable
	lda #$7f
	sta $dd0d
	lda $dd0d
	rts

; LoadLevel — IOINIT + blank + LoadPrg. DEN off (blank_screen) until the
; caller's first swap_view. load_in_play=1 also masks CIA2 NMI (game left
; CIA2 running); timers keep running so IEC still works with DEN=0.
; C=0 ok, C=1 error. Caller must re-init IRQs/ZP (see restart_level).
LoadLevel
	sei
	lda #$35
	sta $01
	lda #$7f
	sta $dc0d				; kill game Timer A IRQ before KERNAL
	lda $dc0d
	lda #0
	sta $d01a				; raster still latches if $d01a=1 after SEI
	lda $d019
	sta $d019
	lda #$2b				; blank before IOINIT can restore DEN
	sta $d011
	lda #$36
	sta $01
	jsr $ff84				; IOINIT — cold and 2nd+ in-play
	lda #$35
	sta $01
	lda load_in_play
	beq .ll_blank
	jsr load_cia2_nmi_off
.ll_blank
	jsr blank_screen			; DEN off after IOINIT
	lda #$36
	sta $01
	cli
	jsr FormatDosName
	lda #4
	ldx #<level_dos_name
	ldy #>level_dos_name
	jmp LoadPrg

}

; restart_level — reload current episode/level map and re-init actors
; Preserves lives; caller resets HP/keys and (on death/new game) ammo/weapons.
; LoadLevel clobbers ZP/CIA — recover like game_start.
restart_level
	lda #1
	sta load_in_play
	jsr LoadLevel
	lda #0
	sta load_in_play
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

	lda #$34
	sta $01					; I/O out — enemy block spans $D000–$DFFF
	jsr doors_clear
	jsr find_spawn
	jsr enemies_init
	lda #$35
	sta $01
	jsr refresh_weapon
	clc
.rl_fail
	rts
