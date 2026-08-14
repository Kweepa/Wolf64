; VIC setup - TechDesignDoc chunky view via multicolor bitmap nibbles
; Double-buffer: SCREEN $4000 / SCREEN_B $4400, flip via $d018
!zone vic

D018_SCR_A	= %00001000			; matrix $4000, bitmap $6000
D018_SCR_B	= %00011000			; matrix $4400, bitmap $6000

init_vic
	lda $dd00
	and #%11111100
	ora #%00000010
	sta $dd00

	lda $d011
	and #%10011111
	ora #%00110000
	sta $d011
	lda $d016
	ora #%00011000			; 40 columns + multicolor
	sta $d016

	lda #D018_SCR_A
	sta $d018
	lda #1
	sta view_back			; first paint -> $4400 while A is shown

	lda #0
	sta $d020
	sta $d021

	; Bitmap + screen + colour RAM loaded from disk (SCR/BMP/COL)
	jsr set_view_rows
	rts

; Point view_row0..23 so painters' cells 2..21 = screen rows 5..24.
; view_row0 -> matrix row 3; unused row slots 0..1 sit in the UI band.
set_view_rows
	lda #$78				; +120 = row 3
	sta tmp0
	lda view_back
	beq .base_a
	lda #>SCREEN_B
	bne .base_hi
.base_a
	lda #>SCREEN
.base_hi
	sta tmp1
	ldx #0
.svr_loop
	lda tmp0
	sta view_row0,x
	lda tmp1
	sta view_row0+1,x
	inx
	inx
	clc
	lda tmp0
	adc #40
	sta tmp0
	bcc +
	inc tmp1
+
	cpx #48
	bne .svr_loop
	rts

; Show the matrix just painted; flip view_back for next frame
swap_view
	lda #$35
	sta $01					; $d018 needs I/O in
	lda view_back
	beq .show_a
	lda #D018_SCR_B
	sta $d018
	lda #0
	sta view_back
	beq .io_out
.show_a
	lda #D018_SCR_A
	sta $d018
	lda #1
	sta view_back
.io_out
	lda #$34
	sta $01
	; SCREEN vs SCREEN_B differ by $04 in the high byte
	ldx #1
-
	lda view_row0,x
	eor #$04
	sta view_row0,x
	inx
	inx
	cpx #49
	bcc -
	rts

; Front matrix hi after swap (opposite of next back)
; -> scr_front_l/h for HUD writes
set_scr_front
	lda #0
	sta scr_front_l
	lda view_back
	beq .front_b
	lda #>SCREEN
	sta scr_front_h
	rts
.front_b
	lda #>SCREEN_B
	sta scr_front_h
	rts

