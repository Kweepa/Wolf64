; Enemy helpers in pre-MAP gap (freed when gfx moved to SFX_BASE)
!zone enemy_hi

; X = enemy — set e_hitscan, e_frm, e_flip from state/type/view
enemy_pick_frm
	lda enemy_state,x
	cmp #ES_SHOOT
	bne +
	jmp .epf_shoot
+
	cmp #ES_BITE
	bne +
	jmp .epf_bite
+
	cmp #ES_PAIN
	bne +
	jmp .epf_pain
+
	cmp #ES_DYING
	bne +
	jmp .epf_dying
+
	cmp #ES_DEAD
	bne +
	jmp .epf_dead
+
	lda #1
	sta e_hitscan
	jmp .epf_live
.epf_bite
	lda #1
	sta e_hitscan
	lda enemy_flags,x
	and #EF_SHOT_DONE
	bne .epf_bj2
	lda #EF_DOG_JUMP1
	bne .epf_bjf
.epf_bj2
	lda #EF_DOG_JUMP2
.epf_bjf
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_shoot
	lda #1
	sta e_hitscan
	lda enemy_type,x
	cmp #ET_HANS
	bne +
	jmp .epf_hans_sh
+
	lda enemy_flags,x
	and #EF_SHOT_DONE
	bne .epf_sh3
	lda #EF_SHOOT2
	bne .epf_shf
.epf_sh3
	lda #EF_SHOOT3
.epf_shf
	sta e_frm
	ldy enemy_type,x
	clc
	lda e_frm
	adc enemy_gfx_base,y
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_hans_sh
	lda enemy_burst,x
	cmp #4
	bcs .epf_hs1
	cmp #2
	bcs .epf_hs2
	lda #EF_HANS_SHOOT3
	bne .epf_hsf
.epf_hs2
	lda #EF_HANS_SHOOT2
	bne .epf_hsf
.epf_hs1
	lda #EF_HANS_SHOOT1
.epf_hsf
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_pain
	lda #1
	sta e_hitscan
	lda enemy_type,x
	cmp #ET_DOG
	beq .epf_dog_pain
	cmp #ET_HANS
	beq .epf_hans_pain
	lda #EF_PAIN
	sta e_frm
	ldy enemy_type,x
	clc
	lda e_frm
	adc enemy_gfx_base,y
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_dog_pain
	lda #EF_DOG_DIE
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_hans_pain
	lda #EF_HANS_DIE1
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_dying
	lda #0
	sta e_hitscan
	lda enemy_type,x
	cmp #ET_DOG
	beq .epf_dog_die
	cmp #ET_HANS
	beq .epf_hans_die
	lda #EF_DIE
	sta e_frm
	ldy enemy_type,x
	clc
	lda e_frm
	adc enemy_gfx_base,y
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_dog_die
	lda enemy_state_t,x
	cmp #42
	bcc .epf_dd3
	lda #EF_DOG_DIE
	bne .epf_ddf
.epf_dd3
	lda #EF_DOG_DIE3
.epf_ddf
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_hans_die
	lda enemy_state_t,x
	cmp #56
	bcs .epf_hd1
	cmp #28
	bcs .epf_hd2
	lda #EF_HANS_DIE3
	bne .epf_hdf
.epf_hd2
	lda #EF_HANS_DIE2
	bne .epf_hdf
.epf_hd1
	lda #EF_HANS_DIE1
.epf_hdf
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_dead
	lda #0
	sta e_hitscan
	lda enemy_type,x
	cmp #ET_DOG
	beq .epf_dog_dead
	cmp #ET_HANS
	beq .epf_hans_dead
	lda #EF_DEAD
	sta e_frm
	ldy enemy_type,x
	clc
	lda e_frm
	adc enemy_gfx_base,y
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_dog_dead
	lda #EF_DOG_DEAD
	sta e_frm
	lda #0
	sta e_flip
	rts
.epf_hans_dead
	lda #EF_HANS_DEAD
	sta e_frm
	lda #0
	sta e_flip
	rts

.epf_live
	lda enemy_type,x
	cmp #ET_DOG
	bne +
	jmp .epf_dog_live
+
	cmp #ET_HANS
	bne +
	jmp .epf_hans_live
+
	lda enemy_flags,x
	and #EF_AMBUSH
	bne .epf_stand
	lda enemy_state,x
	cmp #ES_CHASE
	beq .epf_walkchk
	lda enemy_flags,x
	and #EF_MOVING
	beq .epf_stand
.epf_walkchk
	lda enemy_flags,x
	and #EF_MOVING
	beq .epf_stand
	lda enemy_flags,x
	and #EF_PHASE_B
	bne .epf_wb
	lda #EF_WALKA
	bne .epf_base
.epf_wb
	lda #EF_WALKB
	bne .epf_base
.epf_stand
	lda #EF_STAND
.epf_base
	sta e_frm_base
	lda e_view
	cmp #5
	bcc .epf_noflip
	sec
	sbc #5
	tay
	lda .epf_flip,y
	sta e_src_i
	lda #1
	sta e_flip
	bne .epf_idx
.epf_noflip
	sta e_src_i
	lda #0
	sta e_flip
.epf_idx
	clc
	lda e_frm_base
	adc e_src_i
	ldy enemy_type,x
	adc enemy_gfx_base,y
	sta e_frm
	rts

.epf_dog_live
	lda enemy_flags,x
	and #EF_PHASE_B
	bne .epf_dwb
	lda #EF_DOG_WALKA
	bne .epf_dbase
.epf_dwb
	lda #EF_DOG_WALKB
.epf_dbase
	sta e_frm_base
	lda e_view
	cmp #5
	bcc .epf_dnf
	sec
	sbc #5
	tay
	lda .epf_flip,y
	sta e_src_i
	lda #1
	sta e_flip
	bne .epf_didx
.epf_dnf
	sta e_src_i
	lda #0
	sta e_flip
.epf_didx
	clc
	lda e_frm_base
	adc e_src_i
	sta e_frm
	rts

.epf_hans_live
	lda enemy_flags,x
	and #EF_PHASE_B
	bne .epf_hw2
	lda #EF_HANS_W1
	bne .epf_hwf
.epf_hw2
	lda #EF_HANS_W2
.epf_hwf
	sta e_frm
	lda #0
	sta e_flip
	rts

.epf_flip
	!byte 3, 2, 1				; views 5,6,7 → src 3,2,1

; Spawn at (tmp2,tmp3), tile tmp4, ptr tmp0; X = free slot
enemy_spawn_one
	stx enemy_idx
	lda tmp4
	cmp #T_BOSS
	bne .eso_faced
	lda #ET_HANS
	sta enemy_type,x
	lda #0
	sta enemy_facing,x
	lda #EF_ACTIVE
	sta enemy_flags,x
!if DBG_NO_DETECT = 1 {
	lda #ES_ALIVE			; stand still for patrol preview
} else {
	lda #ES_CHASE
}
	sta enemy_state,x
	jmp .eso_common
.eso_faced
	and #3
	asl					; map NESW → 8-dir cardinal (0,2,4,6)
	sta enemy_facing,x
	lda tmp4
	cmp #T_DOG
	bcc .eso_ss
	lda #ET_DOG
	sta enemy_type,x
	lda #EF_ACTIVE
	sta enemy_flags,x
	lda #ES_ALIVE
	sta enemy_state,x
	jmp .eso_common
.eso_ss
	cmp #T_SS_PATROL
	bcc .eso_guard
	lda #ET_SS
	sta enemy_type,x
	lda tmp4
	cmp #T_SS_AMBUSH
	bcc .eso_ss_pat
	lda #EF_ACTIVE | EF_AMBUSH
	bne .eso_ss_fl
.eso_ss_pat
	lda #EF_ACTIVE
.eso_ss_fl
	sta enemy_flags,x
	lda #ES_ALIVE
	sta enemy_state,x
	jmp .eso_common
.eso_guard
	lda #ET_GUARD
	sta enemy_type,x
	lda tmp4
	cmp #T_AMBUSH
	bcc .eso_gpat
	lda #EF_ACTIVE | EF_AMBUSH
	bne .eso_gfl
.eso_gpat
	lda #EF_ACTIVE
.eso_gfl
	sta enemy_flags,x
	lda #ES_ALIVE
	sta enemy_state,x
.eso_common
	lda tmp2
	sta enemy_xh,x
	lda tmp3
	sta enemy_yh,x
	lda #$80
	sta enemy_xl,x
	sta enemy_yl,x
	lda #0
	sta enemy_anim_t,x
	sta enemy_view,x
	sta enemy_state_t,x
	sta enemy_burst,x
	ldy enemy_type,x
	lda enemy_hp_tab,y
	sta enemy_hp,x
	lda #T_FLOOR
	ldy #0
	sta (tmp0),y
	inx
	stx enemy_count
	rts

; ---------------------------------------------------------------------------
; Patrol turn — tmp0/tmp1 = pre-step xl/yl. Center-cross on T_TURN → snap + face.
; ---------------------------------------------------------------------------
enemy_patrol_turn
	lda tmp0
	pha
	lda tmp1
	pha
	ldx enemy_idx
	lda enemy_xh,x
	sta tmp0
	lda enemy_yh,x
	sta tmp1
	jsr map_to_tile
	ldy #0
	lda (tile_l),y
	tay
	pla
	sta tmp1
	pla
	sta tmp0
	tya
	cmp #T_TURN
	bcc .ept_rts
	cmp #T_TURN + 8
	bcs .ept_rts
	sec
	sbc #T_TURN
	sta tmp5
	lda #0
	sta tmp4
	ldx enemy_idx
	lda move_dx_l
	ora move_dx_h
	beq .ept_y
	lda enemy_xl,x
	cmp tmp0
	beq .ept_y
	lda move_dx_h
	sta tmp3
	lda enemy_xl,x
	ldy tmp0
	jsr .ept_axis
	bcc .ept_rts
.ept_y
	lda move_dy_l
	ora move_dy_h
	beq .ept_ck
	lda enemy_yl,x
	cmp tmp1
	beq .ept_ck
	lda move_dy_h
	sta tmp3
	lda enemy_yl,x
	ldy tmp1
	jsr .ept_axis
	bcc .ept_rts
.ept_ck
	lda tmp4
	beq .ept_rts
	lda #$80
	sta enemy_xl,x
	sta enemy_yl,x
	lda tmp5
	sta enemy_facing,x
.ept_rts
	rts

; A=new frac, Y=old, tmp3=move_*_h. C=1 past center; tmp4++ if was-before.
.ept_axis
	bit tmp3
	bmi .ept_neg
	cmp #$80
	bcc .ept_fail
	cpy #$80
	bcs .ept_ok
	inc tmp4
.ept_ok
	sec
	rts
.ept_neg
	cmp #$80
	beq .ept_n1
	bcs .ept_fail
.ept_n1
	cpy #$80
	beq .ept_ok
	bcc .ept_ok
	inc tmp4
	bne .ept_ok
.ept_fail
	clc
	rts
