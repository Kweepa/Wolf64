; VIC setup — TechDesignDoc chunky view via multicolor bitmap nibbles
!zone vic

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

	lda #%00001000
	sta $d018

	lda #0
	sta $d020
	sta $d021

	jsr fill_bitmap_pattern
	jsr clear_screens
	jsr draw_ui_row
	rts

fill_bitmap_pattern
	; Each char row = 40 cells × 8 bytes = 320 (old loop stopped at Y wrap = 32 cells)
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
	inx
	bne -
	rts

draw_ui_row
	; Placeholder until first frame; tex ids drawn each frame
	ldx #39
	lda #0
-
	sta SCREEN,x
	sta $d800,x
	dex
	bpl -
	rts

; Top row: hex digit 0-9A-F of col_texid[col] in MCM bitmap (00/11 pairs)
draw_texid_row
	ldx #0
.dtr_col
	lda col_texid,x
	and #15
	asl
	asl
	asl					; ×8
	clc
	adc #<hexfont
	sta tmp0
	lda #0
	adc #>hexfont
	sta tmp1

	; BITMAP + col*8 (row 0) — must keep ASL carry (col≥32 → +$100)
	lda #0
	sta tmp3
	txa
	asl
	rol tmp3
	asl
	rol tmp3
	asl
	rol tmp3
	clc
	adc #<BITMAP
	sta tmp2
	lda tmp3
	adc #>BITMAP
	sta tmp3

	ldy #0
.dtr_copy
	lda (tmp0),y
	sta (tmp2),y
	iny
	cpy #8
	bne .dtr_copy

	lda #$00				; 01/10 → black
	sta SCREEN,x
	lda #7					; 11 → yellow
	sta $d800,x

	inx
	cpx #40
	bne .dtr_col
	rts

; Narrow 4×8 MCM glyphs (only center bit-pairs — no edge bleed)
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

blit_fb
	ldx #0
.bl_col
	lda colbaselo,x
	sta col_base_l
	lda colbasehi,x
	sta col_base_h

	txa
	clc
	adc #<(SCREEN + 40)
	sta tmp0
	lda #>(SCREEN + 40)
	adc #0
	sta tmp1

	ldy #0
.bl_row
	lda (col_base_l),y
	sty tmp2
	ldy #0
	sta (tmp0),y
	ldy tmp2

	clc
	lda tmp0
	adc #40
	sta tmp0
	bcc .bl_nc
	inc tmp1
.bl_nc
	iny
	cpy #24
	beq .bl_nextcol
	jmp .bl_row
.bl_nextcol
	inx
	cpx #40
	beq .bl_done
	jmp .bl_col
.bl_done
	rts
