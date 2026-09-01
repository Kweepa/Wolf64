; splashc.prg — Koala matrix/colour at $4000, then do_splash helpers after SPLASH_BG.
; Boot (load $0801) LOADs this, then JSR do_splash: copy colour, clear bitmap, MCM on,
; LOAD splash pixels, LOAD MENU. Helpers overlap SFX_BASE; SFX loads much later.
!cpu 6502
!to "../generated/splashc.prg", cbm

!source "mem.asm"

clr_ptr		= $fb

*= SCREEN
!binary "../generated/splashc_data.bin"
!if * != do_splash {
	!error "splashc data size mismatch; pc=$", *
}

	jsr copy_splash_col
	jsr clear_bitmap
	jsr splash_vic			; matrix + colour RAM live; bitmap black

	lda #6
	ldx #<name_splash
	ldy #>name_splash
	jsr load_sa1
	bcs .fail
	jsr splash_vic			; KERNAL LOAD RMW of $dd00; keep bank 1

	lda #4
	ldx #<name_menu
	ldy #>name_menu
	jsr load_sa1
	bcs .fail
	jsr splash_vic
	rts
.fail
	lda #$35
	sta $01
.hang
	jmp .hang

copy_splash_col
	ldx #0
.csc
	lda SPLASH_COL,x
	sta KOALA_COL_RAM,x
	lda SPLASH_COL + $100,x
	sta KOALA_COL_RAM + $100,x
	lda SPLASH_COL + $200,x
	sta KOALA_COL_RAM + $200,x
	inx
	bne .csc
	ldx #0
.csc_t
	lda SPLASH_COL + $300,x
	sta KOALA_COL_RAM + $300,x
	inx
	cpx #KOALA_TAIL
	bne .csc_t
	lda SPLASH_BG
	sta $d021
	sta $d020
	rts

clear_bitmap
	lda #<BITMAP
	sta clr_ptr
	lda #>BITMAP
	sta clr_ptr + 1
	ldx #32
	lda #0
	tay
.cb
	sta (clr_ptr),y
	iny
	bne .cb
	inc clr_ptr + 1
	dex
	bne .cb
	rts

splash_vic
	lda #%00000010			; VIC bank 1; upper 6 bits 0
	sta $dd00
	lda $d011
	and #%10000111			; clear ECM/BMM/DEN/RSEL
	ora #%00111011			; bitmap + DEN + 25 rows
	sta $d011
	lda $d016
	and #%11100111
	ora #%00011000			; CSEL + MCM
	sta $d016
	lda #%00001000			; matrix $4000, bitmap $6000
	sta $d018
	lda #0
	sta $d015
	sta $d01a
	lda SPLASH_BG
	sta $d021
	sta $d020
	rts

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

name_splash
	!text "SPLASH"
name_menu
	!text "MENU"

end_splashc = *
!if end_splashc > BITMAP {
	!error "splashc helpers overlap bitmap; end=$", end_splashc
}
