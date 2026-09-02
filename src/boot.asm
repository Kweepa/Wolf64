; Wolf64 disposable boot — fits LOADER_BASE..effects_vol.
; LOAD splashc @ $4000 → JSR do_splash (colour, pixels, MENU; Krill install) → JSR menu
; → ENEMY stage + JSR copy_enemy (+3) → file_tab → JMP $0900.
; USE_KRILL=1: loadraw after splashc installed Krill. Default: KERNAL $FFD5.
; File-table index in .xi (KERNAL LOAD clobbers ZP — do not keep ptr in $ae/$af).
!cpu 6502
!to "../generated/boot.prg", cbm

!source "mem.asm"

MENU_COPY_ENEMY	= LOCODE_BASE + 3

*= LOADER_BASE
!byte $0b, $08, $0a, $00, $9e, $32, $30, $36, $31, $00, $00, $00	; SYS 2061

*= $080d
boot_start
	lda #BANK_IO
	sta $01
	jsr $ff84				; IOINIT
	lda $d011
	and #%11101111				; DEN off until colour is in
	sta $d011
	lda #0
	sta $38					; mouse_en (menu detect)
	sta $39					; joy_en
	sta $d020				; border shows even with DEN=0
	sta $d015
	sta $d01a
	cli

	lda #7
	ldx #<name_splashc
	ldy #>name_splashc
	jsr load_sa1
	bcs boot_fail
	jsr do_splash
	jsr LOCODE_BASE				; run difficulty select

	; ENEMY → $A000 (PRG header), copy under I/O → $C000 via MENU+3
	ldx #<name_enemy
	ldy #>name_enemy
!if USE_KRILL {
	jsr load_file
} else {
	lda #5
	jsr load_sa1
}
	bcs boot_fail
	jsr MENU_COPY_ENEMY

	ldx #0
.next
!if USE_KRILL {
	lda file_tab,x
	beq .done
	stx .xi
	txa
	clc
	adc #<file_tab
	tax
	lda #>file_tab
	adc #0
	tay
	jsr load_file
	bcs boot_fail
	ldx .xi
.sk
	lda file_tab,x
	inx
	cmp #0
	bne .sk
	jmp .next
} else {
	lda file_tab,x
	beq .done
	sta .len
	inx
	stx .xi
	txa
	clc
	adc #<file_tab
	tax
	ldy #>file_tab
	lda .len
	jsr load_sa1
	bcs boot_fail
	lda .xi
	clc
	adc .len
	tax
	jmp .next
}

.done
	ldx #$ff
	txs					; discard KERNAL/BASIC stack junk
	jmp LOCODE_BASE

boot_fail
	lda #BANK_LOADER
	sta $01
.hang
	jmp .hang

; KERNAL LOAD, SA=1 (address from the PRG header). A=len, X/Y=name.
load_sa1
	jsr $ffbd
	lda #1
	ldx $ba
	ldy #1
	jsr $ffba
	lda #0
	jsr $ffd5
	php
	lda #1
	jsr $ffc3
	plp
	rts

!if USE_KRILL {
; loadraw, dest from PRG header. X/Y = 0-terminated name. Do not IOINIT.
load_file
	sei
	lda #BANK_LOADER
	sta $01
	clc
	jsr loadraw
	php
	lda #BANK_LOADER
	sta $01
	lda #%00000010
	sta $dd00
	plp
	rts
}

.len	!byte 0
.xi	!byte 0

!if USE_KRILL {
file_tab
	!text "LOCODE"
	!byte 0
	!text "SCR"
	!byte 0
	!text "SFX"
	!byte 0
	!text "BJH"
	!byte 0
	!text "WPN"
	!byte 0
	!text "ITM"
	!byte 0
	!text "BMP"
	!byte 0
	!text "SQT"
	!byte 0
	!text "TEXLO"
	!byte 0
	!text "PAINT"
	!byte 0
	!text "TAB"
	!byte 0
	!text "COL"
	!byte 0
	!byte 0
name_enemy
	!text "ENEMY"
	!byte 0
} else {
file_tab
	!byte 6
	!text "LOCODE"
	!byte 3
	!text "SCR"
	!byte 3
	!text "SFX"
	!byte 3
	!text "BJH"
	!byte 3
	!text "WPN"
	!byte 3
	!text "ITM"
	!byte 3
	!text "BMP"
	!byte 3
	!text "SQT"
	!byte 5
	!text "TEXLO"
	!byte 5
	!text "PAINT"
	!byte 3
	!text "TAB"
	!byte 3
	!text "COL"
	!byte 0
name_enemy
	!text "ENEMY"
}

name_splashc
	!text "SPLASHC"

end_boot = *
!if end_boot > effects_vol {
	!error "Boot overlaps effects_vol/difficulty; end=$", end_boot
}
