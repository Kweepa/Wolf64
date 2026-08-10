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

	jsr fill_bitmap_pattern
	jsr clear_screens
	jsr fill_view_border
	jsr draw_ui_row
	rts

fill_bitmap_pattern
	; Each char row = 40 cells x 8 bytes = 320 (old loop stopped at Y wrap = 32 cells)
	lda #<BITMAP
	sta tmp0
	lda #>BITMAP
	sta tmp1
	ldx #25
.bm_row
	lda #40
	sta tmp2
.bm_cell
	ldy #0
	lda #$55
	sta (tmp0),y
	iny
	sta (tmp0),y
	iny
	sta (tmp0),y
	iny
	sta (tmp0),y
	iny
	lda #$aa
	sta (tmp0),y
	iny
	sta (tmp0),y
	iny
	sta (tmp0),y
	iny
	sta (tmp0),y
	clc
	lda tmp0
	adc #8
	sta tmp0
	bcc +
	inc tmp1
+
	dec tmp2
	bne .bm_cell
	dex
	bne .bm_row
	rts

clear_screens
	ldx #0
	txa
-
	sta SCREEN,x
	sta SCREEN+$100,x
	sta SCREEN+$200,x
	sta SCREEN+$2e8,x
	sta SCREEN_B,x
	sta SCREEN_B+$100,x
	sta SCREEN_B+$200,x
	sta SCREEN_B+$2e8,x
	inx
	bne -
	rts

draw_ui_row
	; Clear top 5 rows (fat wolf UI placeholder); profiler uses row 0
	lda #<(SCREEN)
	sta tmp0
	lda #>(SCREEN)
	sta tmp1
	jsr .dui_five
	lda #<(SCREEN_B)
	sta tmp0
	lda #>(SCREEN_B)
	sta tmp1
	jsr .dui_five
	ldx #0
	lda #0
-
	sta $d800,x				; colour RAM rows 0..4
	inx
	cpx #200
	bne -
	rts
.dui_five
	ldx #200				; 5*40
	lda #0
	tay
-
	sta (tmp0),y
	iny
	dex
	bne -
	rts

; Viewport on screen rows 5..24 (cols 0/39 black). Rows 0..4 = UI (untouched).
fill_view_border
	lda #<(SCREEN + 200)
	sta tmp0
	lda #>(SCREEN + 200)
	sta tmp1
	jsr .fvb_one
	lda #<(SCREEN_B + 200)
	sta tmp0
	lda #>(SCREEN_B + 200)
	sta tmp1
.fvb_one
	ldx #20					; rows 5..24
.fvb_row
	ldy #0
	lda #0
	sta (tmp0),y			; col 0
	ldy #39
	sta (tmp0),y			; col 39
	clc
	lda tmp0
	adc #40
	sta tmp0
	bcc +
	inc tmp1
+
	dex
	bne .fvb_row
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
	lda view_back
	beq .show_a
	lda #D018_SCR_B
	sta $d018
	lda #0
	sta view_back
	rts
.show_a
	lda #D018_SCR_A
	sta $d018
	lda #1
	sta view_back
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

; Narrow 4x8 MCM glyphs (only center bit-pairs - no edge bleed)
hexfont
	!byte $3c,$cc,$cc,$cc,$cc,$cc,$3c,$00	; 0
	!byte $30,$30,$30,$30,$30,$30,$30,$00	; 1
	!byte $3c,$0c,$0c,$3c,$c0,$c0,$fc,$00	; 2
	!byte $3c,$0c,$0c,$3c,$0c,$0c,$3c,$00	; 3
	!byte $cc,$cc,$cc,$fc,$0c,$0c,$0c,$00	; 4
	!byte $fc,$c0,$c0,$fc,$0c,$0c,$fc,$00	; 5
	!byte $3c,$c0,$c0,$fc,$cc,$cc,$3c,$00	; 6
	!byte $fc,$0c,$0c,$30,$30,$30,$30,$00	; 7
	!byte $3c,$cc,$cc,$3c,$cc,$cc,$3c,$00	; 8
	!byte $3c,$cc,$cc,$3c,$0c,$0c,$3c,$00	; 9
	!byte $3c,$cc,$cc,$fc,$cc,$cc,$cc,$00	; A
	!byte $fc,$cc,$cc,$fc,$cc,$cc,$fc,$00	; B
	!byte $3c,$cc,$c0,$c0,$c0,$cc,$3c,$00	; C
	!byte $f0,$cc,$cc,$cc,$cc,$cc,$f0,$00	; D
	!byte $fc,$c0,$c0,$f0,$c0,$c0,$fc,$00	; E
	!byte $fc,$c0,$c0,$f0,$c0,$c0,$c0,$00	; F
