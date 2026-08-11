; Wolf64 disposable boot — fits LOADER_BASE..LOCODE_BASE-1.
; ENEMY first → $8000, copy to $C000 ($01=$34), then remaining SA=1 loads.
; Per file: SETNAM / SETLFS / LOAD / CLOSE only.
; File-table index in .xi (KERNAL LOAD clobbers ZP — do not keep ptr in $ae/$af).
;
; Border (kept on fail):
;   7 yellow ENEMY (staged)
;   1 white  LOCODE
;   3 cyan   TEX
;   4 purple WPN
;   5 green  PAINT
;   6 blue   SFX
;   9 brown  TAB
!cpu 6502
!to "boot.prg", cbm

!source "mem.asm"

ENEMY_STAGING	= PAINTERS			; $8000 — overwritten later by PAINT

*= LOADER_BASE
!byte $0b, $08, $0a, $00, $9e, $32, $30, $36, $31, $00, $00, $00	; SYS 2061

*= $080d
boot_start
	lda #$36
	sta $01
	jsr $ff84				; IOINIT
	cli

	; ENEMY → $8000 (SA=0), copy under I/O → $C000
	lda #7
	sta $d020
	lda #5
	ldx #<name_enemy
	ldy #>name_enemy
	jsr $ffbd
	lda #1
	ldx #8
	ldy #0
	jsr $ffba
	lda #0
	ldx #<ENEMY_STAGING
	ldy #>ENEMY_STAGING
	jsr $ffd5
	bcs .fail
	lda #1
	jsr $ffc3
	jsr copy_enemy

	ldx #0
.next
	lda file_tab,x
	beq .done
	sta $d020
	inx
	lda file_tab,x
	sta .len
	inx
	stx .xi
	txa
	clc
	adc #<file_tab
	tax
	lda #>file_tab
	adc #0
	tay
	lda .len
	jsr load_sa1
	bcs .fail
	lda .xi
	clc
	adc .len
	tax
	jmp .next

.done
	jmp LOCODE_BASE

.fail
	lda #$35
	sta $01
.hang
	jmp .hang

load_sa1
	jsr $ffbd
	lda #1
	ldx #8
	ldy #1
	jsr $ffba
	lda #0
	jsr $ffd5
	php
	lda #1
	jsr $ffc3
	plp
	rts

; ENEMY_SIZE bytes $8000 → $C000, I/O out
copy_enemy
	sei
	lda #$34
	sta $01
	lda #0
	sta $bb
	sta $fd
	lda #>ENEMY_STAGING
	sta $bc
	lda #>ENEMY_BASE
	sta $fe
	ldx #>(ENEMY_SIZE)
	ldy #0
.pg
	lda ($bb),y
	sta ($fd),y
	iny
	bne .pg
	inc $bc
	inc $fe
	dex
	bne .pg
	ldx #<(ENEMY_SIZE)
.tail
	lda ($bb),y
	sta ($fd),y
	iny
	dex
	bne .tail
	lda #$36
	sta $01
	cli
	rts

.len	!byte 0
.xi	!byte 0

file_tab
	!byte 1, 6
	!text "LOCODE"
	!byte 3, 3
	!text "TEX"
	!byte 4, 3
	!text "WPN"
	!byte 5, 5
	!text "PAINT"
	!byte 6, 3
	!text "SFX"
	!byte 9, 3
	!text "TAB"
	!byte 0

name_enemy
	!text "ENEMY"

end_boot = *
!if end_boot > LOCODE_BASE {
	!error "Boot overlaps LOCODE_BASE; end=$", end_boot
}
