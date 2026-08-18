; World item draw — linked at ITEM_SPRITES after gfx blob
!zone items_draw

; A = frame. C=1 collected (treasure), C=0 leave (unknown / prop)
item_try_treasure
	cmp #IF_CROSS
	bcc .itt_no
	cmp #IF_CROWN + 1
	bcs .itt_no
	sec
	sbc #IF_CROSS
	tay
	lda .itt_pts,y
	jsr score_add
	lda #SOUND_BONUS1
	jsr play_sound
	sec
	rts
.itt_no
	clc
	rts
.itt_pts
	!byte 1, 5, 10, 50			; cross, chalice, chest, crown

; A = signed sintab/costab (−64..64) → (A*3)>>6 tile steps (−3..3)
item_dir_tiles
	sta e_acc_l
	bpl .idt_pos
	eor #$ff
	clc
	adc #1
.idt_pos
	sta e_acc_h				; abs
	asl
	clc
	adc e_acc_h				; *3 (max 192)
	lsr
	lsr
	lsr
	lsr
	lsr
	lsr					; /64
	bit e_acc_l
	bpl .idt_out
	eor #$ff
	clc
	adc #1
.idt_out
	rts

; A = signed tile → clamp 0..63
item_clamp63
	bpl +
	lda #0
	rts
+
	cmp #64
	bcc +
	lda #63
+
	rts

; ---------------------------------------------------------------------------
; X = item — fill vis_perp + vis_depth = perp − SPRITE_Z_BIAS (mid-tile $80).
item_calc_depth
	stx enemy_idx
	sec
	lda #$80
	sbc playerx_l
	sta e_dx_l
	lda item_x,x
	sbc playerx_h
	sta e_dx_h
	sec
	lda #$80
	sbc playery_l
	sta e_dy_l
	lda item_y,x
	sbc playery_h
	sta e_dy_h

	ldy playera
	lda costab,y
	sta e_mul
	lda e_dx_l
	sta aux_l
	lda e_dx_h
	sta aux_h
	jsr enemy_mul_s16x8
	sta e_acc_l
	stx e_acc_h

	ldy playera
	lda sintab,y
	sta e_mul
	lda e_dy_l
	sta aux_l
	lda e_dy_h
	sta aux_h
	jsr enemy_mul_s16x8
	sta tmp0
	stx tmp1
	sec
	lda e_acc_l
	sbc tmp0
	sta e_acc_l
	lda e_acc_h
	sbc tmp1
	sta e_acc_h
	bmi .icd_far
	asl e_acc_l
	rol e_acc_h
	bcs .icd_far
	asl e_acc_l
	rol e_acc_h
	bcs .icd_far

	; stash true perp → vis_perp[vis_i]
	ldy vis_i
	lda e_acc_l
	sta vis_perp_l,y
	lda e_acc_h
	sta vis_perp_h,y

	; vis_depth = perp − SPRITE_Z_BIAS, saturate at 0
	lda e_acc_l
	sec
	sbc #SPRITE_Z_BIAS
	sta e_acc_l
	lda e_acc_h
	sbc #0
	sta e_acc_h
	bcs .icd_store
	lda #0
	sta e_acc_l
	sta e_acc_h
	beq .icd_store
.icd_far
	lda #$ff
	sta e_acc_l
	sta e_acc_h
	ldy vis_i
	sta vis_perp_l,y
	sta vis_perp_h,y
.icd_store
	ldy vis_i
	lda e_acc_l
	sta vis_depth_l,y
	lda e_acc_h
	sta vis_depth_h,y
	rts

; ---------------------------------------------------------------------------
item_draw_one
	stx enemy_idx
	ldx vis_tok
	lda vis_depth_h,x
	cmp #$ff
	bne +
	lda vis_depth_l,x
	cmp #$ff
	bne +
	rts
+
	lda vis_depth_h,x
	ora vis_depth_l,x
	bne +
	rts
+
	lda vis_depth_h,x
	bne +
	lda vis_depth_l,x
	cmp #32
	bcs +
	rts
+
	lda vis_depth_l,x
	sta wallz_l
	lda vis_depth_h,x
	sta wallz_h
	jsr calc_half_h
	jsr enemy_calc_spr_h

	lda #0
	sta e_hitscan
	sta e_flip

	ldx enemy_idx
	lda item_frm,x
	sta e_frm
	tay
	lda item_frm_w,y
	sta e_frm_w
	lda item_frm_h,y
	sta e_frm_h

	; mid-tile delta + side; perp from vis_perp[vis_tok]
	ldx enemy_idx
	sec
	lda #$80
	sbc playerx_l
	sta e_dx_l
	lda item_x,x
	sbc playerx_h
	sta e_dx_h
	sec
	lda #$80
	sbc playery_l
	sta e_dy_l
	lda item_y,x
	sbc playery_h
	sta e_dy_h

	ldx vis_tok
	lda vis_perp_l,x
	sta item_perp_l
	lda vis_perp_h,x
	sta item_perp_h
	bpl +
	jmp .ido_rts
+
	jsr enemy_side_from_delta

	lda e_side_l
	sta tmp0
	lda e_side_h
	sta tmp1
	bpl +
	sec
	lda #0
	sbc tmp0
	sta tmp0
	lda #0
	sbc tmp1
	sta tmp1
+
	lda item_perp_h
	lsr
	sta tmp3
	lda item_perp_l
	ror
	sta tmp2
	lsr tmp3
	ror tmp2
	lda tmp2
	ora tmp3
	bne +
	lda #1
	sta tmp2
+
	lda tmp1
	cmp tmp3
	bcc +
	bne .ido_rts
	lda tmp0
	cmp tmp2
	beq +
	bcs .ido_rts
+
	jsr project_col_from_side
	jmp .ido_sized
.ido_rts
	rts

.ido_sized
	ldy e_frm_w
	lda e_spr_h
	jsr mul_8x8
	stx tmp0
	lsr
	ror tmp0
	lsr
	ror tmp0
	lsr
	ror tmp0
	lsr
	ror tmp0
	lda tmp0
	lsr
	bne +
	lda #1
+
	sta e_scr_w

	ldy e_frm_h
	lda e_spr_h
	jsr mul_8x8
	stx tmp0
	lsr
	ror tmp0
	lsr
	ror tmp0
	lsr
	ror tmp0
	lsr
	ror tmp0
	lda tmp0
	bne +
	lda #1
+
	sta tmp2

	ldx e_frm
	lda item_frm_ceil,x
	bne .ido_ceil
	jsr sprite_clamp_floor_h
	clc
	lda #24
	adc half_h
	sta e_bot
	sec
	sbc tmp2
	bcs +
	lda #0
+
	sta e_top
	jmp .ido_clip
.ido_ceil
	; e_bot = 24 + paint_h - half_h (borrow → off the top)
	; e_top may wrap negative; clip treats N as above the view.
	clc
	lda #24
	adc tmp2
	sec
	sbc half_h
	bcc .ido_clip_off
	sta e_bot
	sec
	sbc tmp2
	sta e_top
.ido_clip
	lda e_bot
	cmp #5
	bcc .ido_clip_off
	lda #0
	sta e_clip_skip
	lda e_top
	bmi .ido_clip_up			; wrapped: above v=0
	cmp #44
	bcs .ido_clip_off			; fully below view
	cmp #4
	bcs .ido_clip_bot
.ido_clip_up
	lda #4
	sec
	sbc e_top				; also correct for wrapped e_top
	sta e_clip_skip
	lda #4
	sta e_top
.ido_clip_bot
	lda e_bot
	cmp #44
	bcc +
	lda #44
	sta e_bot
+
	lda e_top
	cmp e_bot
	bcc +
.ido_clip_off
	rts
+
	lda e_scr_w
	lsr
	sta tmp0
	sec
	lda e_col_cx
	sbc tmp0
	sta e_col0

	ldy e_frm
	clc
	lda #<item_gfx_data
	adc item_frm_off_lo,y
	sta e_gfx_l
	lda #>item_gfx_data
	adc item_frm_off_hi,y
	sta e_gfx_h

	lda e_scr_w
	asl
	bne +
	lda #2
+
	sta e_u_denom
	lda e_frm_w
	sta e_u_numer
	lda #0
	sta e_scol_raw
.ido_uinit
	lda e_u_numer
	cmp e_u_denom
	bcc .ido_uready
	sec
	sbc e_u_denom
	sta e_u_numer
	inc e_scol_raw
	bne .ido_uinit
.ido_uready
	lda #$ff
	sta e_scol_cache
	jsr enemy_hitscan_patch

	lda #0
	sta e_sx
.ido_cloop
	lda e_sx
	cmp e_scr_w
	bcc .ido_cgo
	rts
.ido_cgo
	clc
	lda e_col0
	adc e_sx
	sta col
	cmp #COL_FIRST
	bcc .ido_cnxt
	cmp #COL_LIMIT
	bcs .ido_cnxt
	ldx vis_tok
	lda vis_depth_h,x
	ldx col
	cmp col_wallz_h,x
	bcc .ido_zok
	bne .ido_cnxt
	ldx vis_tok
	lda vis_depth_l,x
	ldx col
	cmp col_wallz_l,x
	bcs .ido_cnxt
.ido_zok
	lda e_scol_raw
	cmp e_frm_w
	bcc +
	lda e_frm_w
	sec
	sbc #1
+
	sta e_scol
	jsr enemy_paint_col
.ido_cnxt
	lda e_frm_w
	asl
	clc
	adc e_u_numer
	sta e_u_numer
.ido_uadv
	lda e_u_numer
	cmp e_u_denom
	bcc .ido_uok
	sec
	sbc e_u_denom
	sta e_u_numer
	inc e_scol_raw
	bne .ido_uadv
.ido_uok
	inc e_sx
	jmp .ido_cloop

; tmp0:tmp1 / tmp2:tmp3 → tmp4 = min(quot, 40). Unsigned. tmp5 preserved.
div_q40
	lda tmp2
	ora tmp3
	bne +
	lda #40
	sta tmp4
	rts
+
	lda tmp3
	bne .d16
	lda tmp1
	bne .d168
	lda #0
	sta tmp4
	lda tmp0
	beq .out
.d88
	cmp tmp2
	bcc .out
	sbc tmp2
	inc tmp4
	ldx tmp4
	cpx #40
	bcc .d88
.out
	rts
.d168
	ldx #16
	lda #0
.d168l
	asl tmp0
	rol tmp1
	rol
	bcs .d168s
	cmp tmp2
	bcc .d168n
.d168s
	sbc tmp2
	inc tmp0
.d168n
	dex
	bne .d168l
	lda tmp1
	bne .sat
	lda tmp0
	cmp #41
	bcc .d168o
.sat
	lda #40
.d168o
	sta tmp4
	rts
.d16
	lda #0
	sta tmp4
.d16l
	lda tmp1
	cmp tmp3
	bcc .out
	bne .d16s
	lda tmp0
	cmp tmp2
	bcc .out
.d16s
	sec
	lda tmp0
	sbc tmp2
	sta tmp0
	lda tmp1
	sbc tmp3
	sta tmp1
	inc tmp4
	lda tmp4
	cmp #40
	bcc .d16l
	rts

; e_col_cx = 20 ± min(30, |side|*20 / perp_mid). In: e_side, tmp2:tmp3 = perp>>2
project_col_from_side
	lda #0
	sta tmp5
	lda e_side_l
	sta aux_l
	lda e_side_h
	sta aux_h
	bpl .mul
	inc tmp5
	jsr neg_aux
.mul
	ldy aux_l
	lda #20
	jsr mul_8x8
	stx tmp0
	sta tmp1
	lda aux_h
	beq .div
	tay
	lda #20
	jsr mul_8x8
	txa
	clc
	adc tmp1
	sta tmp1
.div
	jsr div_q40
	lda tmp4
	cmp #30
	bcc +
	lda #30
	sta tmp4
+
	lda tmp5
	bne .add
	sec
	lda #20
	sbc tmp4
	sta e_col_cx
	rts
.add
	clc
	lda #20
	adc tmp4
	sta e_col_cx
	rts
