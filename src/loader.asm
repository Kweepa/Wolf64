; Disk load helpers — resident in locode (map load + restart).
; Same KERNAL sequence as boot: SETNAM / SETLFS / LOAD / CLOSE.
; Caller pages KERNAL in and IOINITs before first load if needed.
;
; Border while loading (kept on failure):
;   8 orange  E1M1 / LoadLevel
!zone loader

LEVEL_DEVICE	= 8

level_dos_name
	!text "E1M1"

; FormatDosName — "ENMM" from episode (0→E1) + level_num (1→M1)
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

; LoadLevel — IOINIT + FormatDosName + LoadPrg. C=0 ok, C=1 error.
LoadLevel
	lda #8					; orange = map
	sta $d020
	lda #$36
	sta $01
	jsr $ff84				; IOINIT
	cli
	jsr FormatDosName
	lda #4
	ldx #<level_dos_name
	ldy #>level_dos_name
	jmp LoadPrg

; restart_level — reload current episode/level map and re-init actors
restart_level
	jsr LoadLevel
	bcs .rl_fail
	jsr doors_clear
	jsr find_spawn
	jsr enemies_init
	jsr init_weapon
	clc
.rl_fail
	rts
