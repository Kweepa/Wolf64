; Disk load helpers — resident in locode (map load + restart).
; Same KERNAL sequence as boot: SETNAM / SETLFS / LOAD / CLOSE.
; Caller pages KERNAL in and IOINITs before first load if needed.
;
; Screen border blacked during LoadLevel (DEN stays on).
!zone loader

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

; Black border/bg, sprites off during load. Keep DEN on — if restart
; aborts before init_vic, DEN=0 would leave a permanent black screen.
blank_screen
	lda #0
	sta $d015
	sta $d020
	sta $d021
	rts

; IOINIT can leave CIA2 Timer A generating NMIs. Quiesce CIA2 while
; loading; prof_init restarts both timers afterward for frame timing.
load_cia2_quiet
	lda #0
	sta $dd0e
	sta $dd0f
	sta $02a1				; KERNAL CIA2 ICR shadow; prevent FE88 re-enable
	lda #$7f
	sta $dd0d
	lda $dd0d
	rts

; LoadLevel — IOINIT + blank + LoadPrg.
; load_in_play=0: cold path (locode_entry) — IOINIT + cli like boot.
; load_in_play=1: IOINIT (reset IEC bus), init_vic (fix VIC), then
; keep SEI through $ffd5. KERNAL serial LOAD is polled and needs no IRQ.
; C=0 ok, C=1 error. Caller must re-init IRQs/ZP (see restart_level).
LoadLevel
	sei
	lda #$35
	sta $01
	lda #$7f
	sta $dc0d				; kill game Timer A IRQ before KERNAL
	lda $dc0d
	lda load_in_play
	beq .ll_cold
	lda #$36
	sta $01
	jsr $ff84				; reset IEC (2nd+ in-play load needs this)
	lda #$35
	sta $01
	jsr load_cia2_quiet
	jsr init_vic				; undo IOINIT charset before blank/load
	jmp .ll_common
.ll_cold
	lda #$36
	sta $01
	jsr $ff84				; IOINIT — cold only
	lda #$35
	sta $01
	jsr load_cia2_quiet
.ll_common
	lda #$35
	sta $01
	jsr blank_screen
	lda #$36
	sta $01
	lda load_in_play
	bne .ll_inplay
	cli
	jsr FormatDosName
	lda #4
	ldx #<level_dos_name
	ldy #>level_dos_name
	jmp LoadPrg

.ll_inplay
	jsr FormatDosName
	lda #4
	ldx #<level_dos_name
	ldy #>level_dos_name
	jmp LoadPrg

; restart_level — reload current episode/level map and re-init actors
; Preserves owned_weapons / ammo / score / lives (caller sets HP/keys as needed).
; LoadLevel IOINITs + KERNAL LOAD clobber ZP/CIA — recover like game_start.
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
	lda #$ff
	sta smc_last_page
	sta smc_last_h

	lda #$34
	sta $01					; I/O out — enemy block spans $D000–$DFFF
	jsr doors_clear
	jsr find_spawn
	jsr enemies_init
	jsr items_init
	lda #$35
	sta $01
	jsr refresh_weapon
	clc
.rl_fail
	rts
