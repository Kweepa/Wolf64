; The Keep–style DDA for a 64×64 Wolf64 map
; Solid: tile in 1..15; walkable: 0 or >=16
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

render_frame
	jsr setup_player_tile
	lda #0
	sta col
.col_loop
	jsr cast_column
	inc col
	lda col
	cmp #40
	bne .col_loop
	jsr blit_fb
	jmp draw_texid_row

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

	; Secant indices from |angle| so ±θ share ddx/ddy (old fold broke L/R symmetry)
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
	jmp .tile0
.ysouth
	lda #1
	sta ystep
	lda fracy_inv
	jsr calc_sdy

.tile0
	lda mapx
	sta tmp0
	lda mapy
	sta tmp1
	jsr map_to_tile

	lda #MAX_DDA
	sta tmp3			; step budget (keep X free)
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
	lda xstep
	bmi .ax_neg
	inc mapx
	inc tile_l
	bne .ax_read
	inc tile_h
	jmp .ax_read
.ax_neg
	dec mapx
	lda tile_l
	bne +
	dec tile_h
+
	dec tile_l
.ax_read
	ldy #0
	lda (tile_l),y
	beq .ax_miss
	cmp #16
	bcs .ax_miss
	; Doors not drawn yet — treat as open
	cmp #11
	bcc .ax_hit
	cmp #14
	bcc .ax_miss
.ax_hit
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
	dec tmp3
	beq .miss
	jmp .inner

.adv_y
	lda ystep
	bmi .ay_neg
	inc mapy
	clc
	lda tile_l
	adc #64
	sta tile_l
	bcc .ay_read
	inc tile_h
	jmp .ay_read
.ay_neg
	dec mapy
	sec
	lda tile_l
	sbc #64
	sta tile_l
	bcs .ay_read
	dec tile_h
.ay_read
	ldy #0
	lda (tile_l),y
	beq .ay_miss
	cmp #16
	bcs .ay_miss
	cmp #11
	bcc .ay_hit
	cmp #14
	bcc .ay_miss
.ay_hit
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
	dec tmp3
	beq .miss
	jmp .inner

.miss
	lda #0
	ldx col
	sta col_texid,x
	jmp draw_sky_floor

; A = angle → 0..64 secant index; fold_angle(|θ|) so fold(θ)=fold(−θ)
fold_angle
	cmp #128
	bcc .fa_pos
	eor #$ff
	clc
	adc #1
.fa_pos
	cmp #64
	bcc .fa_done
	sta tmp1
	lda #128
	sec
	sbc tmp1
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

	; half_h = min(50, max(1, $2000 / wallz)) half-tiles
	jsr calc_half_h
	jmp draw_column

; wallz 8.8 → half_h in 1..50 half-tiles
calc_half_h
	lda wallz_l
	ora wallz_h
	bne +
	lda #50
	sta half_h
	rts
+
	lda #0
	sta tmp0				; quotient
	lda #$00
	sta tmp2				; dividend lo
	lda #$20
	sta tmp3				; dividend hi = $2000
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
	cmp #50
	bcc .sublp
.divdone
	lda tmp0
	bne +
	lda #1
+
	sta half_h
	rts
