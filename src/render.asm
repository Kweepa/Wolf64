; Column dispatch — compiled height painters (TechDesignDoc §4)
; Textures: 16 × 128-byte stripes at TEXTURES ($4800)
!zone render

SKY_COLOR	= $bb
FLOOR_COLOR	= $cc

; A = texture id. Patch table: count, then (addr_lo, addr_hi, byte_off)*
; addr points at LDA abs,x operand lo; written as TEXTURES+id*128+byte_off.
patch_painter_tex
	cmp smc_last_page
	bne .do
	ldx half_h
	cpx smc_last_h
	beq .out
.do
	sta smc_last_page
	sta tmp3
	ldx half_h
	stx smc_last_h

	lda #0
	sta tex_ptr_h
	lda tmp3
	sta tex_ptr_l
	ldx #7
.mul128
	asl tex_ptr_l
	rol tex_ptr_h
	dex
	bne .mul128
	clc
	lda tex_ptr_l
	adc #<TEXTURES
	sta tex_ptr_l
	lda tex_ptr_h
	adc #>TEXTURES
	sta tex_ptr_h

	ldx half_h
	lda ph_patch_lo,x
	sta tmp0
	lda ph_patch_hi,x
	sta tmp1
	ldy #0
	lda (tmp0),y
	beq .out
	sta tmp2
	iny
.loop
	lda (tmp0),y
	sta move_dx_l
	iny
	lda (tmp0),y
	sta move_dx_h
	iny
	lda (tmp0),y
	sta tmp3				; byte_off
	iny
	tya
	pha
	clc
	lda tmp3
	adc tex_ptr_l
	ldy #0
	sta (move_dx_l),y
	lda tex_ptr_h
	adc #0
	iny
	sta (move_dx_l),y
	pla
	tay
	dec tmp2
	bne .loop
.out
	rts

; Paint one column from DDA caches (col_texid / col_half_h / col_texx)
; Uses view_row* (set_view_rows); Y = column, X = texx*8
paint_column
	ldx col
	lda col_texid,x
	bpl .have_tex			; $ff = miss (tex 0 is gold locked door)
	jmp draw_sky_floor

.have_tex
	lda col_half_h,x
	bne +
	lda #1
+
	cmp #MAX_HALF_H + 1
	bcc +
	lda #MAX_HALF_H
+
	sta half_h

	lda col_texx,x
	sta texx

	lda col_texid,x
	jsr patch_painter_tex

	lda texx
	asl
	asl
	asl
	tax
	ldy half_h
	lda painter_lo,y
	sta .pj+1
	lda painter_hi,y
	sta .pj+2
	ldy col
.pj	jmp $0000

; Active cells 2..21 only (top/bottom 2 are static border)
draw_sky_floor
	ldy col
	lda #SKY_COLOR
	sta (view_row2),y
	sta (view_row3),y
	sta (view_row4),y
	sta (view_row5),y
	sta (view_row6),y
	sta (view_row7),y
	sta (view_row8),y
	sta (view_row9),y
	sta (view_row10),y
	sta (view_row11),y
	lda #FLOOR_COLOR
	sta (view_row12),y
	sta (view_row13),y
	sta (view_row14),y
	sta (view_row15),y
	sta (view_row16),y
	sta (view_row17),y
	sta (view_row18),y
	sta (view_row19),y
	sta (view_row20),y
	sta (view_row21),y
	rts
