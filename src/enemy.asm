; Enemies — SoA pool, patrol/chase/shoot/bite, depth-sorted masked billboards
!zone enemy

MAX_ENEMIES	= 32
T_GUARD		= 52				; +0..3 NESW patrol
T_AMBUSH	= 56				; +0..3 NESW ambush
T_SS_PATROL	= 60				; +0..3 NESW
T_SS_AMBUSH	= 64				; +0..3 NESW
T_DOG		= 68				; +0..3 NESW
T_BOSS		= 72				; Hans = 72 (other boss subtypes ignored)
T_FLOOR		= 17
T_TURN		= 112				; +0..7 N,NE,E,SE,S,SW,W,NW
ET_GUARD	= 0
ET_SS		= 1
ET_DOG		= 2
ET_HANS		= 3
EF_ACTIVE	= $01
EF_AMBUSH	= $02
EF_PHASE_B	= $04				; walk A/B toggle (frame bases in enemy_gfx.asm)
EF_MOVING	= $08				; moved this frame → walk anim
EF_FIRSTATTACK	= $10				; allow 180° on first chase dir pick
EF_SHOT_DONE	= $20				; shoot recover / bite already applied
EF_DODGE_FACE	= $40				; RR dodge: keep facing for next chase move
ES_ALIVE	= 0
ES_CHASE	= 1
ES_SHOOT	= 2
ES_BITE		= 3				; dog melee
ES_PAIN		= 4
ES_DYING	= 5
ES_DEAD		= 6
GUARD_HP	= 6				; Wolf 25 / 4
SS_HP		= 25				; Wolf 100 / 4
DOG_HP		= 1				; Wolf 1 (min 1 after /4)
HANS_HP		= 255				; byte max (Wolf boss >> 4)
PLAYER_HP0	= 100
PAIN_T		= 42				; flinch in 8ms units (~336ms)
DIE_T		= 84				; die1 dwell in 8ms units (~672ms)
SHOOT_T		= 50				; ~400ms per aim/recover phase (8ms units)
BURST_GAP	= 12				; ~96ms between SS/Hans shots
BITE_T		= 60				; dog jump/bite dwell (~480ms)
BITE_HIT_T	= 30				; apply bite when timer crosses this
BITE_GAP	= 150				; ~1.2s chase cooldown before next bite
BITE_RANGE	= $c0				; 8.8 P_ApproxDistance (|dx|+|dy|-min/2)
ENEMY_SPEED	= 36				; (const*dt_ms)>>8 → ~0.55 tile/s (Wolf SPDPATROL)
CHASE_SPEED	= 108				; ×3 patrol (Wolf guard FirstSighting)
DOG_CHASE_SPEED	= 108				; same as CHASE_SPEED for now
ANIM_MS		= 180
AIM_COL		= 20				; view-center hit column
DOOR_LOS_MIN	= $80				; door_pos must be ≥ half open for LOS
THINK_DIST	= 12				; Chebyshev tiles: no AI (move/LOS/shoot) beyond this

; Facing 0..7 N,NE,E,SE,S,SW,W,NW → playera-compatible angle
enemy_face_ang
	!byte 64, 32, 0, 224, 192, 160, 128, 96
; opposite facing (+4 mod 8)
enemy_opp_face
	!byte 4, 5, 6, 7, 0, 1, 2, 3
; ET_* → HP
enemy_hp_tab
	!byte GUARD_HP, SS_HP, DOG_HP, HANS_HP
; ET_* → shots per volley (dogs unused)
enemy_burst_tab
	!byte 1, 4, 1, 6
; ET_* → gfx base for guard-layout sheets (dog/Hans unused here)
enemy_gfx_base
	!byte 0, 35, 0, 0			; EG_GUARD, EG_SS

; ---------------------------------------------------------------------------
; Deathchase / SquareDoom GetRandom8 — new = 9 * old + 193; A = next rnd
GetRandom8
rnd8
	lda random8
	asl
	asl
	asl
	clc
	adc random8
	clc
	adc #193
	sta random8
	rts

; ---------------------------------------------------------------------------
enemies_init
	lda #$a5
	sta random8
	lda #0
	sta enemy_count
	sta los_rr
	lda #PLAYER_HP0
	sta player_hp
	ldx #0
.ei_clr
	lda #0
	sta enemy_flags,x
	sta enemy_state,x
	sta enemy_state_t,x
	sta enemy_hp,x
	sta enemy_type,x
	sta enemy_burst,x
	inx
	cpx #MAX_ENEMIES
	bne .ei_clr

	lda #<MAP
	sta tmp0
	lda #>MAP
	sta tmp1
	lda #0
	sta tmp2				; x
	sta tmp3				; y
.ei_loop
	ldy #0
	lda (tmp0),y
	sta tmp4				; tile id
	cmp #T_GUARD
	bcc .ei_next
	cmp #T_BOSS + 1			; 52..72 (Hans only among bosses)
	bcs .ei_next
	ldx enemy_count
	cpx #MAX_ENEMIES
	bcs .ei_next
	jsr enemy_spawn_one
.ei_next
	inc tmp0
	bne +
	inc tmp1
+
	inc tmp2
	lda tmp2
	cmp #64
	bne .ei_loop
	lda #0
	sta tmp2
	inc tmp3
	lda tmp3
	cmp #64
	bne .ei_loop
	rts

; ---------------------------------------------------------------------------
enemies_update
	; dt in 8ms units for state timers (frames are ~100ms; finer is pointless)
	lda dt_ms
	lsr
	lsr
	lsr					; /8
	sta dt8
	ldx #0
.eu_loop
	cpx enemy_count
	bcc .eu_cont
	jmp .eu_los
.eu_cont
	lda enemy_flags,x
	and #EF_ACTIVE
	bne .eu_active
	jmp .eu_next
.eu_active
	; pain / dying / dead always tick; bite too (melee must finish)
	lda enemy_state,x
	cmp #ES_BITE
	beq .eu_bite_far
	cmp #ES_PAIN
	bcc .eu_may_think		; ALIVE / CHASE / SHOOT
	beq .eu_pain
	cmp #ES_DYING
	beq .eu_dying
	jmp .eu_next			; ES_DEAD — corpse stays
.eu_bite_far
	jmp .eu_bite
.eu_may_think
	; ALIVE / CHASE / SHOOT: no AI beyond THINK_DIST
	jsr enemy_tile_dist
	lda tmp1
	cmp #THINK_DIST
	bcc .eu_think
	lda enemy_flags,x
	and #$ff-EF_MOVING
	sta enemy_flags,x
	jmp .eu_next
.eu_think
	lda enemy_state,x
	beq .eu_alive			; ES_ALIVE
	cmp #ES_CHASE
	beq .eu_chase
	jmp .eu_shoot			; ES_SHOOT
.eu_pain
	lda enemy_state_t,x
	sec
	sbc dt8
	bcs +
	lda #0
+
	sta enemy_state_t,x
	beq +
	jmp .eu_next
+
	lda #ES_CHASE			; alerted → resume chase
	sta enemy_state,x
	jmp .eu_next
.eu_dying
	lda enemy_state_t,x
	sec
	sbc dt8
	bcs +
	lda #0
+
	sta enemy_state_t,x
	beq +
	jmp .eu_next
+
	lda #ES_DEAD
	sta enemy_state,x
	jmp .eu_next
.eu_alive
!if DBG_NO_DETECT = 0 {
	; Hans should not be ALIVE (spawns chasing); belt-and-suspenders
	lda enemy_type,x
	cmp #ET_HANS
	bne +
	lda #ES_CHASE
	sta enemy_state,x
	jmp .eu_chase
+
}
	; reaction countdown after sight (Wolf SightPlayer temp2)
	lda enemy_state_t,x
	beq .eu_idle_ai
	sec
	sbc dt8
	bcs +
	lda #0
+
	sta enemy_state_t,x
	beq +
	jmp .eu_next
+
	jsr first_sighting
	jmp .eu_next
.eu_idle_ai
	lda enemy_flags,x
	and #EF_AMBUSH
	bne .eu_stand
	jsr enemy_patrol_one
	jmp .eu_anim
.eu_stand
	; ambush: stand set only, clear walk bits
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_AMBUSH)
	sta enemy_flags,x
	jmp .eu_next
.eu_chase
	; dogs: bite by approx dist (no LOS); honor post-bite gap
	lda enemy_type,x
	cmp #ET_DOG
	bne .eu_chase_go
	lda enemy_state_t,x
	beq .eu_dog_rng
	sec
	sbc dt8
	bcs +
	lda #0
+
	sta enemy_state_t,x
	jmp .eu_chase_go
.eu_dog_rng
	jsr dog_in_bite_range
	bcs .eu_chase_go			; too far
	lda #ES_BITE
	sta enemy_state,x
	lda #BITE_T
	sta enemy_state_t,x
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_PHASE_B | EF_FIRSTATTACK)
	sta enemy_flags,x			; clear SHOT_DONE for bite hit
	jmp .eu_next
.eu_chase_go
	jsr enemy_chase_one
	jmp .eu_anim
.eu_bite
	stx enemy_idx
	lda enemy_state_t,x
	sec
	sbc dt8
	bcs +
	lda #0
+
	sta enemy_state_t,x
	beq .eu_bite_done
	; apply bite once when timer crosses BITE_HIT_T
	cmp #BITE_HIT_T
	bcs .eu_next_j
	lda enemy_flags,x
	and #EF_SHOT_DONE
	bne .eu_next_j
	lda enemy_flags,x
	ora #EF_SHOT_DONE
	sta enemy_flags,x
	jsr enemy_bite
.eu_next_j
	jmp .eu_next
.eu_bite_done
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_PHASE_B | EF_FIRSTATTACK)
	sta enemy_flags,x
	lda #ES_CHASE
	sta enemy_state,x
	lda #BITE_GAP
	sta enemy_state_t,x			; cooldown before next jump
	jmp .eu_next
.eu_shoot
	stx enemy_idx
	lda enemy_state_t,x
	beq .eu_shoot_ready		; 0 = hold aim for RR, or recover done
	sec
	sbc dt8
	bcs +
	lda #0
+
	sta enemy_state_t,x
	bne .eu_shoot_wait
.eu_shoot_ready
	lda enemy_flags,x
	and #EF_SHOT_DONE
	bne .eu_shoot_done
	; aim done — hold pose until enemy_los_rr fires
	jmp .eu_next
.eu_shoot_wait
	jmp .eu_next
.eu_shoot_done
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_PHASE_B | EF_FIRSTATTACK)
	sta enemy_flags,x
	lda #0
	sta enemy_burst,x
	lda #ES_CHASE
	sta enemy_state,x
	jmp .eu_next
.eu_anim
	; walk phase timer only while moving
	lda enemy_flags,x
	and #EF_MOVING
	bne +
	jmp .eu_next
+
	lda enemy_anim_t,x
	clc
	adc dt_ms
	bcc +
	lda #$ff
+
	cmp #ANIM_MS
	bcc .eu_atim
	lda enemy_flags,x
	eor #EF_PHASE_B
	sta enemy_flags,x
	lda #0
.eu_atim
	sta enemy_anim_t,x
.eu_next
	inx
	beq .eu_los
	jmp .eu_loop
.eu_los
	jsr enemy_los_rr
.eu_done
	rts

; A = speed const → vel_ms = (A * dt_ms) >> 8  (tiles/sec ≈ A*1000/256)
enemy_speed_vel
	tay
	lda dt_ms
	jsr mul_8x8				; X=lo A=hi
	sta vel_ms
	rts

; X = enemy index — step along facing, honor turn tiles
enemy_patrol_one
	stx enemy_idx
	lda #1
	sta probe_doors_pass			; unlocked doors walkable
	; clear moving until a step succeeds
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_AMBUSH | EF_PHASE_B)
	sta enemy_flags,x
	lda enemy_yl,x				; pre-step fracs for center-cross
	pha
	lda enemy_xl,x
	pha
	; wish delta from facing
	lda #0
	sta move_dx_l
	sta move_dx_h
	sta move_dy_l
	sta move_dy_h
	lda enemy_facing,x
	tay
	lda enemy_face_ang,y
	sta tmp4				; angle (scale_vel clobbers Y)
	lda #ENEMY_SPEED
	jsr enemy_speed_vel
	; forward: +cos x, -sin y (same as player)
	ldy tmp4
	lda costab,y
	jsr scale_vel
	lda tmp0
	sta move_dx_l
	lda tmp1
	sta move_dx_h
	ldy tmp4
	lda sintab,y
	jsr neg_a
	jsr scale_vel
	lda tmp0
	sta move_dy_l
	lda tmp1
	sta move_dy_h

	; try X
	ldx enemy_idx
	clc
	lda enemy_xl,x
	adc move_dx_l
	sta tmp2
	lda enemy_xh,x
	adc move_dx_h
	sta tmp3
	sta mapx
	lda enemy_yh,x
	sta mapy
	jsr probe_solid
	bne .ep_y
	ldx enemy_idx
	lda tmp2
	sta enemy_xl,x
	lda tmp3
	sta enemy_xh,x
	lda enemy_flags,x
	ora #EF_MOVING
	sta enemy_flags,x
.ep_y
	ldx enemy_idx
	clc
	lda enemy_yl,x
	adc move_dy_l
	sta tmp2
	lda enemy_yh,x
	adc move_dy_h
	sta tmp3
	lda enemy_xh,x
	sta mapx
	lda tmp3
	sta mapy
	jsr probe_solid
	bne .ep_door
	ldx enemy_idx
	lda tmp2
	sta enemy_yl,x
	lda tmp3
	sta enemy_yh,x
	lda enemy_flags,x
	ora #EF_MOVING
	sta enemy_flags,x
.ep_door
	ldx enemy_idx
	lda enemy_flags,x
	and #EF_MOVING
	beq .ep_turn				; no step → skip push
	jsr enemy_push_walls
	; on a door cell → open / hold (not bump-triggered)
	ldx enemy_idx
	lda enemy_xh,x
	sta mapx
	sta tmp0
	lda enemy_yh,x
	sta mapy
	sta tmp1
	jsr door_is_door_xy
	beq .ep_turn
	jsr try_open_door
.ep_turn
	; pre-step fracs → tmp0/tmp1; apply T_TURN only on center-cross
	pla
	sta tmp0
	pla
	sta tmp1
	jsr enemy_patrol_turn
.ep_out
	lda #0
	sta probe_doors_pass
	ldx enemy_idx
	rts

; ---------------------------------------------------------------------------
; Same WALL_MARGIN as player: borrow player coords → push_walls → write back.
enemy_push_walls
	ldx enemy_idx
	lda playerx_l
	pha
	lda playerx_h
	pha
	lda playery_l
	pha
	lda playery_h
	pha
	lda enemy_xl,x
	sta playerx_l
	lda enemy_xh,x
	sta playerx_h
	lda enemy_yl,x
	sta playery_l
	lda enemy_yh,x
	sta playery_h
	jsr push_walls
	ldx enemy_idx
	lda playerx_l
	sta enemy_xl,x
	lda playerx_h
	sta enemy_xh,x
	lda playery_l
	sta enemy_yl,x
	lda playery_h
	sta enemy_yh,x
	pla
	sta playery_h
	pla
	sta playery_l
	pla
	sta playerx_h
	pla
	sta playerx_l
	rts

; ---------------------------------------------------------------------------
; Draw: cull → depth → sort far→near → project → Z-test columns → mask blit
enemies_draw
	lda enemy_count
	bne +
	rts
+
	; clear hit buffer
	ldx #39
	lda #$ff
-
	sta col_enemy,x
	dex
	bpl -

	lda #0
	sta vis_count
	tax					; slot
.ed_cull
	cpx enemy_count
	bcs .ed_culldone
	lda enemy_flags,x
	and #EF_ACTIVE
	beq .ed_cn
	; |xh - playerx_h| < THINK_DIST
	lda enemy_xh,x
	sec
	sbc playerx_h
	bcs +
	eor #$ff
	clc
	adc #1
+
	cmp #THINK_DIST
	bcs .ed_cn
	lda enemy_yh,x
	sec
	sbc playery_h
	bcs +
	eor #$ff
	clc
	adc #1
+
	cmp #THINK_DIST
	bcs .ed_cn
	; visible
	ldy vis_count
	txa
	sta vis_slot,y
	iny
	sty vis_count
	cpy #MAX_ENEMIES
	bcs .ed_culldone
.ed_cn
	inx
	bne .ed_cull
.ed_culldone
	lda vis_count
	bne +
	rts
+
	; depths for visible
	ldy #0
.ed_dep
	sty vis_i
	lda vis_slot,y
	tax
	jsr enemy_calc_depth
	ldy vis_i
	iny
	cpy vis_count
	bcc .ed_dep

	jsr enemy_sort_depth

	; draw far → near
	lda #0
	sta vis_i
.ed_draw
	ldy vis_i
	cpy vis_count
	bcs .ed_done
	lda vis_slot,y
	tax
	jsr enemy_draw_one
	inc vis_i
	bne .ed_draw
.ed_done
	rts

; X = enemy — fill enemy_depth_l/h (wallz) and enemy_perp_l/h
; perp = forward·delta (×4 wallz). depth = max(perp, octagon≈|δ|) so grazing
; angles can't shrink Z/scale and punch through walls. Screen X / FOV use perp.
enemy_calc_depth
	stx enemy_idx
	; dx
	sec
	lda enemy_xl,x
	sbc playerx_l
	sta e_dx_l
	lda enemy_xh,x
	sbc playerx_h
	sta e_dx_h
	; dy
	sec
	lda enemy_yl,x
	sbc playery_l
	sta e_dy_l
	lda enemy_yh,x
	sbc playery_h
	sta e_dy_h

	; term0 = mid(dx * cos)
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

	; term1 = mid(dy * sin); perp = term0 - term1
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
	bmi .ecd_far				; behind camera
	; perp ×4 → wallz units
	asl e_acc_l
	rol e_acc_h
	bcs .ecd_far
	asl e_acc_l
	rol e_acc_h
	bcs .ecd_far

	; stash true perp for projection / FOV
	ldx enemy_idx
	lda e_acc_l
	sta enemy_perp_l,x
	lda e_acc_h
	sta enemy_perp_h,x

	; approx range = max(|dx|,|dy|) + min/2 (octagon, already 8.8)
	jsr enemy_approx_dist		; → tmp0/tmp1
	; depth = max(perp, approx) for Z-test + sprite scale
	lda e_acc_h
	cmp tmp1
	bcc .ecd_use_approx
	bne .ecd_store
	lda e_acc_l
	cmp tmp0
	bcs .ecd_store
.ecd_use_approx
	lda tmp0
	sta e_acc_l
	lda tmp1
	sta e_acc_h
	jmp .ecd_store
.ecd_far
	lda #$ff
	sta e_acc_l
	sta e_acc_h
	ldx enemy_idx
	sta enemy_perp_l,x
	sta enemy_perp_h,x
.ecd_store
	ldx enemy_idx
	lda e_acc_l
	sta enemy_depth_l,x
	lda e_acc_h
	sta enemy_depth_h,x
	rts

; |e_dx|,|e_dy| → tmp0/tmp1 = max + min/2
enemy_approx_dist
	lda e_dx_l
	sta aux_l
	lda e_dx_h
	sta aux_h
	bpl +
	jsr neg_aux
+
	lda aux_l
	sta tmp2
	lda aux_h
	sta tmp3				; |dx|
	lda e_dy_l
	sta aux_l
	lda e_dy_h
	sta aux_h
	bpl +
	jsr neg_aux
+
	; compare |dx| vs |dy| (aux = |dy|)
	lda tmp3
	cmp aux_h
	bcc .ead_dy
	bne .ead_dx
	lda tmp2
	cmp aux_l
	bcc .ead_dy
.ead_dx
	; max=|dx| min=|dy| → |dx| + |dy|/2
	lsr aux_h
	ror aux_l
	clc
	lda tmp2
	adc aux_l
	sta tmp0
	lda tmp3
	adc aux_h
	sta tmp1
	rts
.ead_dy
	; max=|dy| min=|dx|
	lsr tmp3
	ror tmp2
	clc
	lda aux_l
	adc tmp2
	sta tmp0
	lda aux_h
	adc tmp3
	sta tmp1
	rts

; Signed mid(aux * e_mul) → A=lo X=hi. Both signed.
enemy_mul_s16x8
	lda aux_h
	eor e_mul
	sta tmp4				; sign of product (N bit via BMI)
	lda aux_h
	bpl +
	jsr neg_aux
+
	lda e_mul
	bpl +
	eor #$ff
	clc
	adc #1
+
	jsr mul_16x8				; A=lo X=hi unsigned mid
	sta tmp0
	stx tmp1
	bit tmp4
	bpl .ems_out
	sec
	lda #0
	sbc tmp0
	sta tmp0
	lda #0
	sbc tmp1
	tax
	lda tmp0
	rts
.ems_out
	lda tmp0
	ldx tmp1
	rts

neg_aux
	sec
	lda #0
	sbc aux_l
	sta aux_l
	lda #0
	sbc aux_h
	sta aux_h
	rts

; Insertion sort vis_slot by depth descending (far first)
enemy_sort_depth
	ldx #1
.es_outer
	cpx vis_count
	bcs .es_done
	lda vis_slot,x
	sta tmp0
	stx tmp5
	txa
	tay
.es_inner
	dey
	bmi .es_at0
	sty tmp4
	lda vis_slot,y
	tax
	lda enemy_depth_h,x
	sta tmp1
	lda enemy_depth_l,x
	sta tmp2
	ldx tmp0
	lda enemy_depth_h,x
	cmp tmp1
	bcc .es_place			; new nearer than [y]
	bne .es_shift
	lda enemy_depth_l,x
	cmp tmp2
	bcc .es_place
	beq .es_place
.es_shift
	ldy tmp4
	lda vis_slot,y
	sta vis_slot+1,y
	jmp .es_inner
.es_at0
	lda tmp0
	sta vis_slot
	jmp .es_next
.es_place
	ldy tmp4
	iny
	lda tmp0
	sta vis_slot,y
.es_next
	ldx tmp5
	inx
	cpx vis_count
	bcc .es_outer
.es_done
	rts

; wallz → e_spr_h = $2400/wallz (≡ 3/2 · $1800/wallz), 1..ENEMY_MAX_H
; Finer than (3*half_h)/2 which inherits heightab's wallz>>5 steps.
enemy_calc_spr_h
	lda wallz_l
	ora wallz_h
	bne +
	lda #ENEMY_MAX_H
	sta e_spr_h
	rts
+
	lda #0
	sta tmp0
	lda #$00
	sta tmp2
	lda #$24
	sta tmp3				; dividend $2400
.ecsh_lp
	sec
	lda tmp2
	sbc wallz_l
	tax
	lda tmp3
	sbc wallz_h
	bcc .ecsh_done
	stx tmp2
	sta tmp3
	inc tmp0
	lda tmp0
	cmp #ENEMY_MAX_H
	bcc .ecsh_lp
.ecsh_done
	lda tmp0
	bne +
	lda #1
+
	sta e_spr_h
	rts

; X = enemy — project + paint
enemy_draw_one
	stx enemy_idx
	lda enemy_depth_h,x
	cmp #$ff
	bne +
	lda enemy_depth_l,x
	cmp #$ff
	bne +
	rts					; behind camera
+
	lda enemy_depth_h,x
	ora enemy_depth_l,x
	bne +
	rts					; on top of player
+
	; reject extremely near (unstable / fills view)
	lda enemy_depth_h,x
	bne +
	lda enemy_depth_l,x
	cmp #32
	bcs +
	rts
+
	; wallz = depth for half_h (floor alignment) + fine sprite height
	lda enemy_depth_l,x
	sta wallz_l
	lda enemy_depth_h,x
	sta wallz_h
	jsr calc_half_h
	jsr enemy_calc_spr_h

	; feet on floor in chunky space (40×48): horizon at v=24
	; wall floor edge = 24 + half_h; active v = 4..43 (cells 2..21 → screen rows 5..24)
	; e_bot kept unclamped so close sprites clip off the bottom (not glued to y=44)
	; e_top set later from paint_h = frm_h*spr_h/16
	clc
	lda #24
	adc half_h
	sta e_bot

	; view 0..7: (atan2(to_player) - facing) → octant
	ldx enemy_idx
	; vector enemy → player
	sec
	lda playerx_l
	sbc enemy_xl,x
	sta e_dx_l
	lda playerx_h
	sbc enemy_xh,x
	sta e_dx_h
	sec
	lda playery_l
	sbc enemy_yl,x
	sta e_dy_l
	lda playery_h
	sbc enemy_yh,x
	sta e_dy_h
	jsr enemy_atan2			; A = angle toward player
	sta tmp0
	ldx enemy_idx
	lda enemy_facing,x
	tay
	lda enemy_face_ang,y
	sec
	sbc tmp0
	clc
	adc #16				; round to nearest octant
	lsr
	lsr
	lsr
	lsr
	lsr					; /32
	and #7
	sta enemy_view,x
	sta e_view

	jsr enemy_pick_frm

.edo_side
	; screen center from side transform
	jsr enemy_calc_side
	; FOV cull: |side_mid| > perp_mid (perp>>2) → outside ~45°
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
	ldx enemy_idx
	lda enemy_perp_h,x
	lsr
	sta tmp3
	lda enemy_perp_l,x
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
	bne .edo_rts_fov
	lda tmp0
	cmp tmp2
	beq +
	bcs .edo_rts_fov
+
	jsr enemy_project_col
	jmp .edo_sized
.edo_rts_fov
	rts
.edo_sized
	; width in columns: (frm_w * spr_h / SRC_H) / 2 — chunky cells are 8×4 (2:1)
	; Use canonical SRC_H=16, not cropped frm_h (dead is 5px tall → blew up width).
	ldy e_frm
	lda enemy_frm_w,y
	sta e_frm_w
	lda enemy_frm_h,y
	sta e_frm_h
	ldy e_frm_w
	lda e_spr_h
	jsr mul_8x8				; X=lo A=hi
	stx tmp0
	lsr					; /16 (hi in A)
	ror tmp0
	lsr
	ror tmp0
	lsr
	ror tmp0
	lsr
	ror tmp0
	lda tmp0
	lsr					; /2 for aspect
	bne +
	lda #1
+
	sta e_scr_w

	; paint span: (frm_h * spr_h / 16) — short frames skip empty upper rows
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
	sta tmp2				; paint_h
	sec
	lda e_bot
	sbc tmp2
	bcs +
	lda #0					; top above world origin
+
	sta e_top
	; fully below or above the 4..43 view → nothing to paint
	cmp #44
	bcc +
	jmp .edo_done
+
	lda e_bot
	cmp #5
	bcs +
	jmp .edo_done
+
	; clip to view: skip texels for rows above v=4; clamp bot to 44
	lda #0
	sta e_clip_skip
	lda e_top
	cmp #4
	bcs +
	lda #4
	sec
	sbc e_top
	sta e_clip_skip
	lda #4
	sta e_top
+
	lda e_bot
	cmp #44
	bcc +
	lda #44
	sta e_bot
+
	lda e_top
	cmp e_bot
	bcc +
	jmp .edo_done
+

	; left = cx - scr_w/2
	lda e_scr_w
	lsr
	sta tmp0
	sec
	lda e_col_cx
	sbc tmp0
	sta e_col0

	; gfx ptr
	ldy e_frm
	clc
	lda #<enemy_gfx_data
	adc enemy_frm_off_lo,y
	sta e_gfx_l
	lda #>enemy_gfx_data
	adc enemy_frm_off_hi,y
	sta e_gfx_h

	; Bresenham U: scol = (2*sx+1)*frm_w / (2*scr_w)
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
.edo_uinit
	lda e_u_numer
	cmp e_u_denom
	bcc .edo_uready
	sec
	sbc e_u_denom
	sta e_u_numer
	inc e_scol_raw
	bne .edo_uinit
.edo_uready
	lda #$ff
	sta e_scol_cache

	; for each screen column across billboard width
	lda #0
	sta e_sx
.edo_cloop
	lda e_sx
	cmp e_scr_w
	bcc .edo_cgo
	jmp .edo_done
.edo_cgo
	; clip / Z before texture work
	clc
	lda e_col0
	adc e_sx
	sta col
	cmp #COL_FIRST
	bcc .edo_cnxt
	cmp #COL_LIMIT
	bcs .edo_cnxt
	ldx enemy_idx
	lda enemy_depth_h,x
	ldx col
	cmp col_wallz_h,x
	bcc .edo_zok
	bne .edo_cnxt
	ldx enemy_idx
	lda enemy_depth_l,x
	ldx col
	cmp col_wallz_l,x
	bcs .edo_cnxt
.edo_zok
	lda e_scol_raw
	cmp e_frm_w
	bcc +
	lda e_frm_w
	sec
	sbc #1
+
	sta tmp2
	lda e_flip
	beq .edo_sraw
	sec
	lda e_frm_w
	sbc #1
	sec
	sbc tmp2
	jmp .edo_suse
.edo_sraw
	lda tmp2
.edo_suse
	sta e_scol
	jsr enemy_paint_col
.edo_cnxt
	; advance U for every sx (including rejects)
	lda e_frm_w
	asl
	clc
	adc e_u_numer
	sta e_u_numer
.edo_uadv
	lda e_u_numer
	cmp e_u_denom
	bcc .edo_udone
	sec
	sbc e_u_denom
	sta e_u_numer
	lda e_scol_raw
	clc
	adc #1
	cmp e_frm_w
	bcc +
	lda e_frm_w
	sec
	sbc #1
+
	sta e_scol_raw
	jmp .edo_uadv
.edo_udone
	inc e_sx
	jmp .edo_cloop
.edo_done
	ldx enemy_idx
	rts

.flip_src
	!byte 3, 2, 1				; view 5,6,7

; Coarse atan2(e_dx, e_dy) → A angle (0=E, 64=N, 128=W, 192=S)
; 8-way on full 16-bit deltas (fracs matter up close).
; tmp0/1 = |dx| lo/hi, tmp2/3 = |dy| lo/hi; e_abs2 = 2*min scratch.
enemy_atan2
	lda e_dx_l
	sta tmp0
	lda e_dx_h
	sta tmp1
	bpl +
	lda #0
	sec
	sbc tmp0
	sta tmp0
	lda #0
	sbc tmp1
	sta tmp1
+
	lda e_dy_l
	sta tmp2
	lda e_dy_h
	sta tmp3
	bpl +
	lda #0
	sec
	sbc tmp2
	sta tmp2
	lda #0
	sbc tmp3
	sta tmp3
+
	; |dx| >= |dy| ?
	lda tmp0
	cmp tmp2
	lda tmp1
	sbc tmp3
	bcc .ea_dy_dom
	; |dx| >= |dy|: cardinal E/W if 2*|dy| < |dx|
	lda tmp2
	asl
	sta e_abs2_l
	lda tmp3
	rol
	sta e_abs2_h
	lda e_abs2_l
	cmp tmp0
	lda e_abs2_h
	sbc tmp1
	bcc .ea_card_x
	; diagonal
	lda e_dx_h
	bmi .ea_w_diag
	lda e_dy_h
	bmi .ea_ne
	lda #224				; SE
	rts
.ea_ne
	lda #32					; NE
	rts
.ea_w_diag
	lda e_dy_h
	bmi .ea_nw
	lda #160				; SW
	rts
.ea_nw
	lda #96					; NW
	rts
.ea_card_x
	lda e_dx_h
	bmi +
	lda #0					; E
	rts
+
	lda #128				; W
	rts
.ea_dy_dom
	; |dy| > |dx|: cardinal N/S if 2*|dx| < |dy|
	lda tmp0
	asl
	sta e_abs2_l
	lda tmp1
	rol
	sta e_abs2_h
	lda e_abs2_l
	cmp tmp2
	lda e_abs2_h
	sbc tmp3
	bcc .ea_card_y
	lda e_dx_h
	bmi .ea_w_diag2
	lda e_dy_h
	bmi .ea_ne2
	lda #224
	rts
.ea_ne2
	lda #32
	rts
.ea_w_diag2
	lda e_dy_h
	bmi .ea_nw2
	lda #160
	rts
.ea_nw2
	lda #96
	rts
.ea_card_y
	lda e_dy_h
	bmi +
	lda #192				; S
	rts
+
	lda #64					; N
	rts

; side_mid = mid(dx*sin) + mid(dy*cos) — same mid units as depth before ×4
enemy_calc_side
	ldx enemy_idx
	sec
	lda enemy_xl,x
	sbc playerx_l
	sta e_dx_l
	lda enemy_xh,x
	sbc playerx_h
	sta e_dx_h
	sec
	lda enemy_yl,x
	sbc playery_l
	sta e_dy_l
	lda enemy_yh,x
	sbc playery_h
	sta e_dy_h
	ldy playera
	lda sintab,y
	sta e_mul
	lda e_dx_l
	sta aux_l
	lda e_dx_h
	sta aux_h
	jsr enemy_mul_s16x8
	sta e_side_l
	stx e_side_h
	ldy playera
	lda costab,y
	sta e_mul
	lda e_dy_l
	sta aux_l
	lda e_dy_h
	sta aux_h
	jsr enemy_mul_s16x8
	clc
	adc e_side_l
	sta e_side_l
	txa
	adc e_side_h
	sta e_side_h
	rts

; e_col_cx = 20 - (side_mid * 20) / perp_mid  (true forward depth, not octagon)
enemy_project_col
	lda #20
	sta e_col_cx
	ldx enemy_idx
	lda enemy_perp_h,x
	cmp #$ff
	bne .epj_ok
	rts
.epj_ok
	; perp_mid = perp >> 2
	lsr
	sta tmp3
	lda enemy_perp_l,x
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
	; |side_mid| in aux; tmp5 = 1 if side was negative
	lda #0
	sta tmp5
	lda e_side_l
	sta aux_l
	lda e_side_h
	sta aux_h
	bpl .epj_mul
	inc tmp5
	jsr neg_aux
.epj_mul
	; product = |side| * 20 → tmp0:tmp1
	ldy aux_l
	lda #20
	jsr mul_8x8				; X=lo A=hi of side_l*20
	stx tmp0
	sta tmp1
	lda aux_h
	beq .epj_div
	tay
	lda #20
	jsr mul_8x8				; X=lo of side_h*20 → add to tmp1
	txa
	clc
	adc tmp1
	sta tmp1
.epj_div
	; tmp0:tmp1 / tmp2:tmp3 → tmp4 (quot 0..40)
	lda #0
	sta tmp4
.epj_dloop
	lda tmp1
	cmp tmp3
	bcc .epj_ddone
	bne .epj_dsub
	lda tmp0
	cmp tmp2
	bcc .epj_ddone
.epj_dsub
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
	bcc .epj_dloop
.epj_ddone
	lda tmp4
	cmp #30
	bcc +
	lda #30
+
	sta tmp4
	; col = 20 - signed(side)*20/z
	; +side (geometric right / south when facing E) → lower column:
	; angtab left = −angle = south when facing east.
	lda tmp5
	bne .epj_add				; side was − → 20+quot
	sec
	lda #20
	sbc tmp4
	jmp .epj_set
.epj_add
	clc
	lda #20
	adc tmp4
.epj_set
	sta e_col_cx
	rts

; Paint one masked column in chunky rows (two nibbles per character cell).
; e_top/e_bot/e_row are 40×48 chunky V (4..43). Even V = hi nibble, odd = lo.
enemy_paint_col
	lda e_scol
	cmp e_scol_cache
	beq .epc_draw
	sta e_scol_cache
	; column byte offset = scol * ceil(frm_h/2)
	lda e_frm_h
	clc
	adc #1
	lsr					; bytes per col
	ldy e_scol
	jsr mul_8x8				; X=lo A=hi
	stx tmp3
	clc
	lda e_gfx_l
	adc tmp3
	sta e_col_l
	lda e_gfx_h
	adc #0
	sta e_col_h

	; unpack frm_h texels into e_pix[16-frm_h..] (no full clear — upper unused)
	lda #ENEMY_SRC_H
	sec
	sbc e_frm_h
	tax					; dest row = 16 - frm_h
	lda e_frm_h
	sta tmp4				; texels left
	ldy #0
.epc_unp
	lda tmp4
	beq .epc_draw
	lda (e_col_l),y
	sta tmp0
	lsr
	lsr
	lsr
	lsr
	sta e_pix,x
	inx
	dec tmp4
	beq .epc_draw
	lda tmp0
	and #$0f
	sta e_pix,x
	inx
	dec tmp4
	iny
	bne .epc_unp
.epc_draw
	ldx e_spr_h
	lda enemy_vstep_lo,x
	sta e_step_l
	lda enemy_vstep_hi,x
	sta e_step_h
	; start at (16-frm_h) + half step → opaque band centers
	lda e_step_h
	lsr
	sta e_acc_h
	lda e_step_l
	ror
	sta e_acc_l
	lda #ENEMY_SRC_H
	sec
	sbc e_frm_h
	clc
	adc e_acc_h
	sta e_acc_h
	; advance past rows clipped above the view
	ldy e_clip_skip
	beq .epc_row0
.epc_skp
	clc
	lda e_acc_l
	adc e_step_l
	sta e_acc_l
	lda e_acc_h
	adc e_step_h
	sta e_acc_h
	dey
	bne .epc_skp
.epc_row0
	lda e_top
	sta e_row
.epc_row
	lda e_row
	cmp e_bot
	bcs .epc_rts
	; e_top/e_bot already clipped to 4..44
	lda e_acc_h
	cmp #16
	bcc +
	lda #15
+
	tax
	lda e_pix,x
	beq .epc_nr				; 0 = transparent
	sta tmp4
	; hit buffer: nearest opaque writer for this column
	lda e_hitscan
	beq .epc_nobuf
	lda enemy_idx
	ldy col
	sta col_enemy,y
.epc_nobuf
	; cell = v >> 1 → view_row pointer
	lda e_row
	lsr					; A=cell, C=1 if bottom nibble
	php
	asl
	tax
	lda view_row0,x
	sta tmp0
	lda view_row0+1,x
	sta tmp1
	ldy col
	plp
	bcs .epc_lo
	; top half → high nibble
	lda tmp4
	asl
	asl
	asl
	asl
	sta tmp4
	lda (tmp0),y
	and #$0f
	ora tmp4
	sta (tmp0),y
	jmp .epc_nr
.epc_lo
	lda (tmp0),y
	and #$f0
	ora tmp4
	sta (tmp0),y
.epc_nr
	clc
	lda e_acc_l
	adc e_step_l
	sta e_acc_l
	lda e_acc_h
	adc e_step_h
	sta e_acc_h
	inc e_row
	bne .epc_row
.epc_rts
	rts

; ---------------------------------------------------------------------------
; Wolf GunAttack via col_enemy[20/19/21] + DamageActor
; ---------------------------------------------------------------------------
gun_attack
	ldx col_enemy + AIM_COL		; center first
	cpx #$ff
	bne .ga_got
	ldx col_enemy + AIM_COL - 1
	cpx #$ff
	bne .ga_got
	ldx col_enemy + AIM_COL + 1
	cpx #$ff
	beq .ga_miss
.ga_got
	cpx enemy_count
	bcs .ga_miss
	lda enemy_flags,x
	and #EF_ACTIVE
	beq .ga_miss
	lda enemy_state,x
	cmp #ES_DYING
	bcs .ga_miss			; dying/dead not shootable
	; Chebyshev tile distance
	lda enemy_xh,x
	sec
	sbc playerx_h
	bcs +
	eor #$ff
	clc
	adc #1
+
	sta tmp0
	lda enemy_yh,x
	sec
	sbc playery_h
	bcs +
	eor #$ff
	clc
	adc #1
+
	cmp tmp0
	bcs +
	lda tmp0
+
	sta tmp1				; dist
	cmp #2
	bcs .ga_d4
	jsr rnd8
	lsr
	lsr					; /4
	jmp .ga_dmg
.ga_d4
	lda tmp1
	cmp #4
	bcs .ga_far
	jsr rnd8
	jsr .div6
	jmp .ga_dmg
.ga_far
	jsr rnd8
	jsr .div12
	cmp tmp1
	bcc .ga_miss			; (rnd/12) < dist → miss
	jsr rnd8
	jsr .div6
.ga_dmg
	; A = damage — Wolf÷4 so HP/4 stays in one byte; floor 1 if any damage
	beq .ga_miss
	lsr
	lsr
	bne +
	lda #1
+
	; A = damage, X = enemy
	jmp damage_actor
.ga_miss
	rts

; A = value → A = A/6 (unsigned)
.div6
	sta tmp2
	lda #0
	sta tmp3
.d6_lp
	lda tmp2
	cmp #6
	bcc .d6_done
	sbc #6
	sta tmp2
	inc tmp3
	bne .d6_lp
.d6_done
	lda tmp3
	rts

; A = value → A = A/12
.div12
	sta tmp2
	lda #0
	sta tmp3
.d12_lp
	lda tmp2
	cmp #12
	bcc .d12_done
	sbc #12
	sta tmp2
	inc tmp3
	bne .d12_lp
.d12_done
	lda tmp3
	rts

; X = enemy index, A = raw damage (Wolf DamageActor; already ÷4 from gun)
damage_actor
	sta tmp2
	stx enemy_idx
	lda enemy_flags,x
	and #EF_AMBUSH
	beq .da_sub
	asl tmp2				; surprise: double damage
.da_sub
	lda enemy_hp,x
	sec
	sbc tmp2
	bcc .da_kill
	beq .da_kill
	sta enemy_hp,x
	; pain → then chase (alerted)
	lda #ES_PAIN
	sta enemy_state,x
	lda #PAIN_T
	sta enemy_state_t,x
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_PHASE_B)	; clear ambush / shot / moving
	ora #EF_FIRSTATTACK
	sta enemy_flags,x
	lda #SOUND_HITENEMY
	jmp play_sound
.da_kill
	lda #0
	sta enemy_hp,x
	lda #ES_DYING
	sta enemy_state,x
	lda #DIE_T
	sta enemy_state_t,x
	lda #EF_ACTIVE				; keep drawable; drop walk/ambush
	sta enemy_flags,x
	lda #0
	sta enemy_anim_t,x
	lda enemy_type,x
	cmp #ET_DOG
	bne .da_scream
	lda #SOUND_DOGDEATH
	jmp play_sound
.da_scream
	jsr rnd8
	and #3
	cmp #3
	bcc +
	lda #0
+
	tax
	lda .da_screams,x
	jmp play_sound

.da_screams
	!byte SOUND_DEATHSCREAM1, SOUND_DEATHSCREAM2, SOUND_DEATHSCREAM3

; Dog melee — Wolf T_Bite (no LOS); damage = rnd>>4
enemy_bite
	ldx enemy_idx
	jsr dog_in_bite_range
	bcs .eb_rts				; hopped away
	jsr rnd8
	lsr
	lsr
	lsr
	lsr
	beq .eb_rts				; 0 damage — miss
	jmp take_damage
.eb_rts
	ldx enemy_idx
	rts

; C=0 if approx dist to player < BITE_RANGE (Doom P_ApproxDistance)
dog_in_bite_range
	ldx enemy_idx
	sec
	lda enemy_xl,x
	sbc playerx_l
	sta e_dx_l
	lda enemy_xh,x
	sbc playerx_h
	sta e_dx_h
	sec
	lda enemy_yl,x
	sbc playery_l
	sta e_dy_l
	lda enemy_yh,x
	sbc playery_h
	sta e_dy_h
	jsr enemy_approx_dist		; → tmp0/tmp1
	lda tmp1
	bne .dbr_far
	lda tmp0
	cmp #BITE_RANGE
	bcs .dbr_far
	clc
	rts
.dbr_far
	sec
	rts
