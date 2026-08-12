; Wolf64 disposable boot — fits LOADER_BASE..LOCODE_BASE-1.
; ENEMY first → $8000, copy to $C000 ($01=$34), then remaining SA=1 loads.
; Per file: SETNAM / SETLFS / LOAD / CLOSE only.
; File-table index in .xi (KERNAL LOAD clobbers ZP — do not keep ptr in $ae/$af).
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

; ENEMY gap → $C000 (I/O out). SMC abs,x; round up to whole pages
; (map not loaded yet — overcopy into $EFxx is fine).
ENEMY_COPY_PAGES = (MAP - ENEMY_BASE + 255) / 256

copy_enemy
	sei
	lda #$34
	sta $01
	lda #>ENEMY_STAGING
	sta .s + 2
	lda #>ENEMY_BASE
	sta .d + 2
	ldx #0
	ldy #ENEMY_COPY_PAGES
.pg
.s	lda ENEMY_STAGING,x
.d	sta ENEMY_BASE,x
	inx
	bne .pg
	inc .s + 2
	inc .d + 2
	dey
	bne .pg
	lda #$36
	sta $01
	cli
	rts

.len	!byte 0
.xi	!byte 0

file_tab
	!byte 6
	!text "LOCODE"
	!byte 3
	!text "SCR"
	!byte 3
	!text "TEX"
	!byte 3
	!text "WPN"
	!byte 3
	!text "ITM"
	!byte 3
	!text "BMP"
	!byte 3
	!text "SQT"
	!byte 5
	!text "PAINT"
	!byte 3
	!text "SFX"
	!byte 3
	!text "TAB"
	!byte 3
	!text "COL"
	!byte 0

name_enemy
	!text "ENEMY"

end_boot = *
!if end_boot > LOCODE_BASE {
	!error "Boot overlaps LOCODE_BASE; end=$", end_boot
}
