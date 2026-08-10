; The Keep–style DDA for a 64×64 Wolf64 map
; Solid: tile < 16; walkable: >= 16 (empty=16; doors parked at 251..253 for now)
!zone dda

MAX_DDA = 64

setup_player_tile
	lda playerx_l
	sta fracx
	; 256−frac (not 255−frac): at center $80, both axes must match for L/R symmetry
	eor #$ff
	clc
	adc #1
	sta fracx_inv
	lda playerx_h
	sta plr_mapx
	sta mapx
	lda playery_l
	sta fracy
	eor #$ff
	clc
	adc #1
	sta fracy_inv
	lda playery_h
	sta plr_mapy
	sta mapy
	rts

; Pipelined: setup → cast cols 1..38 → paint back → $d018 swap
; Letterbox 38x40 chunky: skip col 0/39 and top/bottom 2 cells (see gen_painters).
; Cast cannot split setup×40 then march×40: SMC tile ops are per-column.
COL_FIRST	= 1
COL_LIMIT	= 39				; exclusive

render_frame
!if PROFILE = 1 {
	jsr prof_reset_frame
}
	jsr setup_player_tile
	lda #COL_FIRST
	sta col
.dda_loop
	jsr cast_column
	inc col
	lda col
	cmp #COL_LIMIT
	bne .dda_loop
!if PROFILE = 1 {
!if PROF_SPLIT = 0 {
	ldy #PROF_CAST
	jsr prof_add_bucket
}
}
	jsr set_view_rows
	; Painters/SMC under $A000 need BASIC out (see hacks.md)
	lda #$34
	sta $01
	lda #COL_FIRST
	sta col
.paint_loop
	jsr paint_column
	inc col
	lda col
	cmp #COL_LIMIT
	bne .paint_loop
	lda #$35
	sta $01
!if PROFILE = 1 {
	ldy #PROF_PAINT
	jsr prof_add_bucket
}
	jsr swap_view
	rts

cast_column
	; Previous column left mapx/mapy at the hit cell — always restart at player
	lda plr_mapx
	sta mapx
	lda plr_mapy
	sta mapy

	ldx col
	lda angtab,x
	clc
	adc playera
	sta angle

	; Secant indices from |angle| so ±θ share ddx/ddy
	lda angle
	jsr fold_angle
	sta dxindex
	tay
	lda fixsecl,y
	sta ddx_l
	lda fixsech,y
	sta ddx_h

	lda angle
	clc
	adc #64
	sta tmp0
	jsr fold_angle
	sta dyindex
	tay
	lda fixsecl,y
	sta ddy_l
	lda fixsech,y
	sta ddy_h

	lda tmp0
	bmi .xn
	lda #1
	sta xstep
	lda fracx_inv
	jsr calc_sdx
	jmp .ys
.xn
	lda #$ff
	sta xstep
	lda fracx
	jsr calc_sdx
.ys
	; 0=east, 64=north: angle 0..127 → −Y, 128..255 → +Y
	lda angle
	bmi .ysouth
	lda #$ff
	sta ystep
	lda fracy
	jsr calc_sdy
	jmp .patch
.ysouth
	lda #1
	sta ystep
	lda fracy_inv
	jsr calc_sdy

.patch
	; SquareDoom: patch ±X/±Y tile advances once per column (no sign tests in march)
	ldx #$e6				; INC zp
	lda xstep
	bpl +
	ldx #$c6				; DEC zp
+
	stx .smc_x_lo
	stx .smc_x_hi
	stx .smc_mapx
	ldx #$18				; CLC
	ldy #$69				; ADC #
	lda ystep
	bpl +
	ldx #$38				; SEC
	ldy #$e9				; SBC #
+
	stx .smc_y_clc
	sty .smc_y_op1
	sty .smc_y_op2
	ldx #$e6				; INC mapy
	lda ystep
	bpl +
	ldx #$c6				; DEC mapy
+
	stx .smc_mapy

	lda mapx
	sta tmp0
	lda mapy
	sta tmp1
	jsr map_to_tile
!if PROFILE = 1 {
!if PROF_SPLIT = 1 {
	ldy #PROF_RAY
	jsr prof_add_bucket
}
}
	jsr cast_march
!if PROFILE = 1 {
!if PROF_SPLIT = 1 {
	ldy #PROF_DDA
	jsr prof_add_bucket
}
}
	rts

; Inner DDA + hit_wall / miss (expects tile_*, ddx/ddy/sdx/sdy, SMC patched)
cast_march
	ldy #0					; Y=0 for (tile_l) reads
	ldx #MAX_DDA				; step budget in X

.inner
	lda sdx_h
	cmp sdy_h
	bcc .adv_x
	bne .adv_y
	lda sdx_l
	cmp sdy_l
	bcs .adv_y

.adv_x
.smc_x_lo
	inc tile_l
	bne .smc_x_ok
.smc_x_hi
	inc tile_h
.smc_x_ok
.smc_mapx
	inc mapx
	lda (tile_l),y
	cmp #16
	bcs .ax_miss
	sta tex_id
	lda #0
	sta side
	lda sdx_l
	sta wallz_l
	lda sdx_h
	sta wallz_h
	jmp hit_wall
.ax_miss
	clc
	lda sdx_l
	adc ddx_l
	sta sdx_l
	lda sdx_h
	adc ddx_h
	sta sdx_h
	bcs .miss
	dex
	beq .miss
	jmp .inner

.adv_y
.smc_y_clc
	clc
	lda tile_l
.smc_y_op1
	adc #64
	sta tile_l
	lda tile_h
.smc_y_op2
	adc #0
	sta tile_h
.smc_mapy
	inc mapy
	lda (tile_l),y
	cmp #16
	bcs .ay_miss
	sta tex_id
	lda #1
	sta side
	lda sdy_l
	sta wallz_l
	lda sdy_h
	sta wallz_h
	jmp hit_wall
.ay_miss
	clc
	lda sdy_l
	adc ddy_l
	sta sdy_l
	lda sdy_h
	adc ddy_h
	sta sdy_h
	bcs .miss				; 16-bit wrap → bogus near wallz / huge column
	dex
	beq .miss
	jmp .inner

.miss
	lda #0
	ldx col
	sta col_texid,x
	sta col_half_h,x
	sta col_texx,x
	rts

; A = angle → 0..64 secant index (Keep-style fold)
fold_angle
	and #127
	cmp #64
	bcc .fa_done
	eor #127
	clc
	adc #1
.fa_done
	rts

map_to_tile
	; tile = MAP + mapy*64 + mapx
	lda #0
	sta tile_l
	lda tmp1
	sta tile_h
	lsr tile_h
	ror tile_l
	lsr tile_h
	ror tile_l
	clc
	lda tile_l
	adc tmp0
	sta tile_l
	lda tile_h
	adc #0
	sta tile_h
	clc
	lda tile_l
	adc #<MAP
	sta tile_l
	lda tile_h
	adc #>MAP
	sta tile_h
	rts

hit_wall
	lda tex_id
	ldx col
	sta col_texid,x

	; Wall U (The Keep hitcommon): face frac from s×fixcos ± player frac
	lda side
	bne .u_y
	lda sdx_l
	sta aux_l
	lda sdx_h
	sta aux_h
	ldy dyindex
	lda fixcos,y
	jsr mul_16x8
	ldx ystep
	ldy fracy
	jmp .u_combine
.u_y
	lda sdy_l
	sta aux_l
	lda sdy_h
	sta aux_h
	ldy dxindex
	lda fixcos,y
	jsr mul_16x8
	ldx xstep
	ldy fracx
.u_combine
	cpx #0
	bmi .u_neg
	clc
	sty tmp0
	adc tmp0
	jmp .u_to_texx
.u_neg
	sec
	sty tmp0
	sbc tmp0
	eor #$ff
.u_to_texx
	lsr					; 16-wide texture (Keep used >>5 for 8-wide)
	lsr
	lsr
	lsr
	and #15
	sta texx

	; Fish-eye: wallz = mid(s × fish)
	lda side
	bne .z_y
	lda sdx_l
	sta aux_l
	lda sdx_h
	sta aux_h
	jmp .z_mul
.z_y
	lda sdy_l
	sta aux_l
	lda sdy_h
	sta aux_h
.z_mul
	ldx col
	lda fishtab,x
	jsr mul_16x8
	sta wallz_l
	stx wallz_h

	; half_h: wallz>>5 → heightab; wallz<32 (close) → exact $1800/wallz
	jsr calc_half_h
	ldx col
	lda half_h
	sta col_half_h,x
	lda texx
	sta col_texx,x
	rts

; wallz 8.8 → half_h in 1..MAX_HALF_H (256-entry heightab, idx = wallz>>5)
; Scale $1800 = 3/4 of former $2000 (squarer tiles)
calc_half_h
	lda wallz_h
	sta tmp1
	lda wallz_l
	lsr tmp1
	ror
	lsr tmp1
	ror
	lsr tmp1
	ror
	lsr tmp1
	ror
	lsr tmp1
	ror					; A = wallz >> 5
	beq .near				; wallz < 32: close, spend on divide
	tax
	lda heightab,x
	sta half_h
	rts
.near
	lda wallz_l
	ora wallz_h
	bne +
	lda #MAX_HALF_H
	sta half_h
	rts
+
	lda #0
	sta tmp0
	lda #$00
	sta tmp2
	lda #$18
	sta tmp3
.sublp
	sec
	lda tmp2
	sbc wallz_l
	tax
	lda tmp3
	sbc wallz_h
	bcc .divdone
	stx tmp2
	sta tmp3
	inc tmp0
	lda tmp0
	cmp #MAX_HALF_H
	bcc .sublp
.divdone
	lda tmp0
	bne +
	lda #1
+
	sta half_h
	rts
