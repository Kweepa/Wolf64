; Column dispatch — compiled height painters (TechDesignDoc §4)
; Textures: 16 × 128-byte stripes at TEXTURES ($4800)
!zone render

SKY_COLOR	= $bb
FLOOR_COLOR	= $cc

; A = texture id. Patch table: count, then (addr_lo, addr_hi, byte_off)*
; addr points at LDA abs,x operand lo; written as TEXTURES+id*128+byte_off.
; ph_h_done[half_h] = tex id already patched for that height ($ff = none).
; Always set tex_ptr (painter_near samples it); skip only the LDA operand walk.
init_ph_h_done
	ldx #MAX_HALF_H
	lda #$ff
-
	sta ph_h_done,x
	dex
	bpl -
	rts

patch_painter_tex
	tay
	lda tex_base_lo,y
	sta tex_ptr_l
	lda tex_base_hi,y
	sta tex_ptr_h
	ldx half_h
	tya
	cmp ph_h_done,x
	beq .out
	sta ph_h_done,x

	lda ph_patch_lo,x
	sta tmp0
	lda ph_patch_hi,x
	sta tmp1
	ldy #0
	lda (tmp0),y
	beq .out
	sta tmp2
	iny
	sty tmp4
.loop
	ldy tmp4
	lda (tmp0),y
	sta move_dx_l
	iny
	lda (tmp0),y
	sta move_dx_h
	iny
	lda (tmp0),y				; byte_off
	iny
	sty tmp4
	clc
	adc tex_ptr_l
	ldy #0
	sta (move_dx_l),y
	lda tex_ptr_h
	adc #0
	iny
	sta (move_dx_l),y
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
	sta tmp3
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

	lda tmp3
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
