; Column painter — sky / wall / floor into FRAMEBUF (24 cells = 48 half-tiles)
; Horizon at half-tile 24; half_h is 1..50 half-tiles (TDD wall-height spectrum)
!zone render

SKY_COLOR	= $bb				; dark grey
FLOOR_COLOR	= $cc				; medium grey

draw_column
	ldx col
	lda colbaselo,x
	sta col_base_l
	lda colbasehi,x
	sta col_base_h

	lda half_h
	bne +
	lda #1
	sta half_h
+
	; Unclipped wall in half-tiles: [24-h, 24+h). Clip to [0,48).
	lda half_h
	cmp #24
	bcc .h_small
	lda #0
	sta wall_top_ht
	lda #48
	sta wall_end_ht
	jmp .prep_tex
.h_small
	lda #24
	sec
	sbc half_h
	sta wall_top_ht
	clc
	lda #24
	adc half_h
	sta wall_end_ht

.prep_tex
	ldx col
	lda col_texid,x
	bne .have_tex
	jmp draw_sky_floor

.have_tex
	; TEXTURES + id*128 + texx*8
	lda #0
	sta tex_ptr_h
	ldx col
	lda col_texid,x
	sta tex_ptr_l
	ldx #7
-
	asl tex_ptr_l
	rol tex_ptr_h
	dex
	bne -
	clc
	lda tex_ptr_l
	adc #<TEXTURES
	sta tex_ptr_l
	lda tex_ptr_h
	adc #>TEXTURES
	sta tex_ptr_h
	lda texx
	asl
	asl
	asl
	clc
	adc tex_ptr_l
	sta tex_ptr_l
	bcc +
	inc tex_ptr_h
+

	ldy #0					; character cell 0..23
.cell
	sty texy_l				; save cell (sample clobbers Y)

	; high nibble = half-tile cell*2
	tya
	asl
	jsr sample_half
	asl
	asl
	asl
	asl
	sta tmp3

	; low nibble = half-tile cell*2+1
	lda texy_l
	asl
	clc
	adc #1
	jsr sample_half
	ora tmp3

	ldy texy_l
	sta (col_base_l),y
	iny
	cpy #24
	bne .cell
	rts

; A = half-tile row 0..47 → A = sky/floor/wall colour nibble
sample_half
	sta tmp0
	cmp wall_top_ht
	bcc .sky
	cmp wall_end_ht
	bcs .floor

	; v = half_row + half_h - 24
	clc
	adc half_h
	sec
	sbc #24
	sta tmp1

	; tex_row = min(15, (v*8) / half_h) with 16-bit dividend
	lda #0
	sta tmp2
	lda tmp1
	asl
	rol tmp2
	asl
	rol tmp2
	asl
	rol tmp2
	sta tmp1				; tmp2:tmp1 = v*8
	ldx #0
.div
	lda tmp2
	bne .sub				; hi≠0 ⇒ ≥ half_h
	lda tmp1
	cmp half_h
	bcc .div_done
.sub
	lda tmp1
	sec
	sbc half_h
	sta tmp1
	bcs +
	dec tmp2
+
	inx
	cpx #16
	bcc .div
	ldx #15
.div_done
	stx texy_h
	jmp fetch_tex_nibble

.sky
	lda #$0b				; dark grey
	rts
.floor
	lda #$0c				; medium grey
	rts

; texy_h = row 0..15 → A = colour nibble (clobbers Y)
fetch_tex_nibble
	lda texy_h
	lsr
	tay
	lda (tex_ptr_l),y
	bcs .odd
	lsr
	lsr
	lsr
	lsr
	rts
.odd
	and #$0f
	rts

draw_sky_floor
	ldx col
	lda colbaselo,x
	sta col_base_l
	lda colbasehi,x
	sta col_base_h
	ldy #0
-
	lda #SKY_COLOR
	sta (col_base_l),y
	iny
	cpy #12
	bne -
-
	lda #FLOOR_COLOR
	sta (col_base_l),y
	iny
	cpy #24
	bne -
	rts
