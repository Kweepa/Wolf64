; The Keep–style DDA for a 64×64 Wolf64 map
; 1..14 solid walls, 15..17 doors, >=18 walkable (empty=18)
!zone dda

MAX_DDA = 64

setup_player_tile
	lda playerx_l
	sta fracx
	; 256−frac (not 255−frac): at center $80, both axes must match for L/R symmetry.
	; frac=0 → 256 wraps to 0 in 8-bit; that makes sdx=0 and pops the view
	; every E/W tile crossing that lands on $00. Use $FF (≈1 tile) instead.
	jsr neg_a
	bne +
	lda #$ff
+
	sta fracx_inv
	lda playerx_h
	sta plr_mapx
	sta mapx
	lda playery_l
	sta fracy
	jsr neg_a
	bne +
	lda #$ff
+
	sta fracy_inv
	lda playery_h
	sta plr_mapy
	sta mapy
	lda #0
	sta dda_last_x
	sta dda_last_y
	lda #$ff
	sta door_cx
	rts

; Pipelined: setup → cast cols 1..38 → paint back → $d018 swap
; Viewport flush bottom: skip col 0/39; painters cells 2..21 → screen rows 5..24.
; Cast cannot split setup×40 then march×40: SMC tile ops are per-column.
COL_FIRST	= 1
COL_LIMIT	= 39				; exclusive

render_frame
	; PROFILE: buckets reset in main_loop before enemies_update
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
	; view_row* flipped in swap_view (eor #$04)
	lda #COL_FIRST
	sta col
.paint_loop
	jsr paint_column
	inc col
	lda col
	cmp #COL_LIMIT
	bne .paint_loop
!if PROFILE = 1 {
	ldy #PROF_PAINT
	jsr prof_add_bucket
}
	jsr enemies_draw
!if PROFILE = 1 {
	ldy #PROF_OBJDRAW
	jsr prof_add_bucket
}
	jmp swap_view

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
	; SquareDoom: patch ±X/±Y once per column; skip if signs match last ray
	lda xstep
	cmp dda_last_x
	bne .smc_do
	lda ystep
	cmp dda_last_y
	beq .smc_ok
.smc_do
	lda xstep
	sta dda_last_x
	lda ystep
	sta dda_last_y
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
.smc_ok

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
; Y stays 0 for lda (tile_l),y — door_try_* restores Y=0 on the continue path
cast_march
	ldx #MAX_DDA				; step budget in X
	ldy #0

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
	cmp #18
	bcs .ax_miss				; walkable — common case
	cmp #15
	bcs .ax_door				; 15..17 door
	sta tex_id
	jmp .hit_x
.ax_door
	jsr door_try_x
	bcc .ax_miss
	jmp hit_door
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
	bne .inner
	beq .miss

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
	cmp #18
	bcs .ay_miss				; walkable — common case
	cmp #15
	bcs .ay_door				; 15..17 door
	sta tex_id
	jmp .hit_y
.ay_door
	jsr door_try_y
	bcc .ay_miss
	jmp hit_door
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
	bne .inner

.miss
	ldx col
	lda #$ff				; miss sentinel (tex 0 = gold lock plate)
	sta col_texid,x
	lda #0
	sta col_half_h,x
	sta col_texx,x
	lda #$ff
	sta col_wallz_l,x
	sta col_wallz_h,x
	rts

.hit_x
	lda #0
	sta side
	lda sdx_l
	sta wallz_l
	lda sdx_h
	sta wallz_h
	jmp hit_wall
.hit_y
	lda #1
	sta side
	lda sdy_l
	sta wallz_l
	lda sdy_h
	sta wallz_h
	jmp hit_wall

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
	; tile = MAP + mapy*64 + mapx  (map_row_* = MAP + y*64)
	ldy tmp1
	lda map_row_lo,y
	clc
	adc tmp0
	sta tile_l
	lda map_row_hi,y
	adc #0
	sta tile_h
	rts

hit_wall
	; Walls beside a door use jamb texture (slot 15)
	jsr door_jamb_check
	lda tex_id
	cmp #T_SECRET_ELEVATOR
	bne +
	lda #T_ELEVATOR
	sta tex_id
+
	; Wall U + fish share aux = sdx (side=0) or sdy (side=1)
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
	and #$f0				; 16-wide texture: texx kept pre-shifted into the high
	sta texx				; nibble (paint_column ORs it with tex_id, no runtime shift)

	ldx col
	lda fishtab,x
	jsr mul_16x8
	sta wallz_l
	stx wallz_h
	jsr calc_half_h
	ldx col
	lda tex_id
	sta col_texid,x
	lda wallz_l
	sta col_wallz_l,x
	lda wallz_h
	sta col_wallz_h,x
	lda half_h
	sta col_half_h,x
	lda texx
	sta col_texx,x
	rts

; wallz 8.8 → half_h in 1..MAX_HALF_H (256-entry heightab, idx = wallz>>5)
; Scale $1800 = 3/4 of former $2000 (squarer tiles)
; wallz>=$2000 → (wallz>>5) high != 0; 8-bit idx would wrap into near heights
; heightab[0] = MAX_HALF_H covers wallz < 32 (old $1800/z subtract always clamped 75)
calc_half_h
	lda wallz_h
	bne .slow
	lda wallz_l
	lsr
	lsr
	lsr
	lsr
	lsr
	tax
	lda heightab,x
	sta half_h
	rts
.slow
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
	ror					; A = (wallz>>5) low; tmp1 = high
	ldx tmp1
	bne .far1				; wallz >= $2000 → half_h = 1
	tax
	lda heightab,x
	sta half_h
	rts
.far1
	lda #1
	sta half_h
	rts
