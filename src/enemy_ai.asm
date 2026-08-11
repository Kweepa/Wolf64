; Enemy AI — LOS, chase, shoot (placed in VIC gap before bitmap)
!zone enemy_ai

; Round-robin: at most one LOS resolve per frame (idle / chase / fire)
; ---------------------------------------------------------------------------
enemy_los_rr
	lda enemy_count
	bne +
	rts
+
	sta tmp5				; probes left
	ldx los_rr
.elr_find
	cpx enemy_count
	bcc +
	ldx #0
+
	lda enemy_flags,x
	and #EF_ACTIVE
	beq .elr_next
	lda enemy_state,x
	beq .elr_idle			; ES_ALIVE
	cmp #ES_CHASE
	beq .elr_chase
	cmp #ES_SHOOT
	beq .elr_shoot
.elr_next
	inx
	stx los_rr
	dec tmp5
	bne .elr_find
	rts
.elr_idle
	lda enemy_state_t,x
	bne .elr_next			; already reacting
	stx enemy_idx
	jsr enemy_tile_dist
	lda tmp1
	cmp #THINK_DIST
	bcs .elr_next			; too far to spot
	stx los_rr
!if PROFILE = 1 {
	jsr prof_los_begin
}
	jsr check_sight
!if PROFILE = 1 {
	php
	jsr prof_los_end
	plp
}
	bcs +
	jmp .elr_adv			; not spotted
+
	; start reaction delay: 1 + rnd/4 (Wolf temp2)
	jsr rnd8
	lsr
	lsr
	clc
	adc #1
	ldx enemy_idx
	sta enemy_state_t,x
	jmp .elr_adv
.elr_chase
	stx enemy_idx
	jsr enemy_tile_dist
	lda tmp1
	cmp #THINK_DIST
	bcs .elr_next			; too far — don't burn LOS slot
	sta ai_dist
	stx los_rr
	jsr enemy_rr_chase
	jmp .elr_adv
.elr_shoot
	lda enemy_state_t,x
	bne .elr_next			; still aiming / recovering
	lda enemy_flags,x
	and #EF_SHOT_DONE
	bne .elr_next			; recover handled in update
	stx enemy_idx
	jsr enemy_tile_dist
	lda tmp1
	cmp #THINK_DIST
	bcc .elr_fire
	; walked out of range — drop aim, no LOS used
	ldx enemy_idx
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_PHASE_B | EF_FIRSTATTACK)
	sta enemy_flags,x
	lda #ES_CHASE
	sta enemy_state,x
	jmp .elr_next
.elr_fire
	; aim done — fire on this LOS slot; burst or recover
	stx los_rr
!if PROFILE = 1 {
	jsr prof_los_begin
}
	jsr enemy_shoot
!if PROFILE = 1 {
	jsr prof_los_end
}
	ldx enemy_idx
	lda enemy_burst,x
	beq .elr_burst1			; safety: treat as last shot
	sec
	sbc #1
	sta enemy_burst,x
	beq .elr_last
	; more shots left — short gap, keep aiming pose
	lda #BURST_GAP
	sta enemy_state_t,x
	jmp .elr_adv
.elr_burst1
	lda #0
	sta enemy_burst,x
.elr_last
	lda enemy_flags,x
	ora #EF_SHOT_DONE
	sta enemy_flags,x
	lda #SHOOT_T
	sta enemy_state_t,x
	jmp .elr_adv
.elr_adv
	ldx los_rr
	inx
	stx los_rr
	rts

; Chase LOS slot: shoot chance or dodge face (enemy_idx + ai_dist set)
enemy_rr_chase
	ldx enemy_idx
	lda enemy_type,x
	cmp #ET_DOG
	bne .erc_gun
	; dogs never shoot — slot used, keep chasing (bite from update)
	rts
.erc_gun
!if PROFILE = 1 {
	jsr prof_los_begin
}
	jsr has_los_to_player
!if PROFILE = 1 {
	php
	jsr prof_los_end
	plp
}
	bcc .erc_rts			; no LOS → slot used, keep chasing
	; chance: close → 48; else min(40, max(1, (dt8<<2)/dist))
	lda ai_dist
	beq .erc_shot
	cmp #1
	bne .erc_ch
.erc_shot
	lda #48
	bne .erc_roll
.erc_ch
	; (dt8<<2) / ai_dist — 8-iter bitdiv, quot in tmp0
	lda dt8
	asl
	asl
	sta tmp0
	lda #0
	sta tmp1				; rem
	ldx #8
.erc_bd
	asl tmp0
	rol tmp1
	lda tmp1
	cmp ai_dist
	bcc .erc_bdn
	sbc ai_dist
	sta tmp1
	inc tmp0
.erc_bdn
	dex
	bne .erc_bd
	lda tmp0
	bne +
	lda #1
+
	cmp #41
	bcc .erc_roll
	lda #40
.erc_roll
	sta tmp3				; chance
	jsr rnd8
	cmp tmp3
	bcs .erc_dodge			; rnd >= chance → dodge face
	; enter shoot with type burst count
	ldx enemy_idx
	lda #ES_SHOOT
	sta enemy_state,x
	lda #SHOOT_T
	sta enemy_state_t,x
	ldy enemy_type,x
	lda enemy_burst_tab,y
	sta enemy_burst,x
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_PHASE_B | EF_FIRSTATTACK)
	sta enemy_flags,x			; clear SHOT_DONE/MOVING/DODGE
.erc_rts
	rts
.erc_dodge
	jsr select_dodge_dir
	ldx enemy_idx
	lda enemy_flags,x
	ora #EF_DODGE_FACE
	sta enemy_flags,x
	rts

; X = enemy. C=1 if spots player (facing + LOS)
check_sight
!if DBG_NO_DETECT = 1 {
	clc					; wander / patrol preview
	rts
}
	stx enemy_idx
	jsr enemy_tile_dist		; tmp1 = Chebyshev dist
	lda tmp1
	cmp #2
	bcc .cs_los			; ≤1 tiles: auto (MINSIGHT stand-in)
	ldx enemy_idx
	lda playerx_h
	sec
	sbc enemy_xh,x
	sta tmp2				; dx
	lda playery_h
	sec
	sbc enemy_yh,x
	sta tmp3				; dy
	lda enemy_facing,x
	tay
	; need_dx/need_dy: 0=any, 1=positive, $ff=negative
	lda .cs_need_dx,y
	beq .cs_cky
	bmi .cs_dxn
	lda tmp2
	beq .cs_fail
	bmi .cs_fail
	bpl .cs_cky
.cs_dxn
	lda tmp2
	bpl .cs_fail
.cs_cky
	lda .cs_need_dy,y
	beq .cs_los
	bmi .cs_dyn
	lda tmp3
	beq .cs_fail
	bpl .cs_los
.cs_fail
	clc
	rts
.cs_dyn
	lda tmp3
	bmi .cs_los
	clc
	rts
.cs_los
	ldx enemy_idx
	jsr has_los_to_player
	rts
; N NE E SE S SW W NW
.cs_need_dx
	!byte 0, 1, 1, 1, 0, $ff, $ff, $ff
.cs_need_dy
	!byte $ff, $ff, 0, 1, 1, 1, 0, $ff

; X = enemy. C=1 if clear LOS. Prefer last-frame col_enemy, else check_line.
has_los_to_player
	stx enemy_idx
	stx tmp4				; want this index
	ldx #COL_FIRST
.hl_scan
	lda col_enemy,x
	cmp tmp4
	beq .hl_yes
	inx
	cpx #COL_LIMIT
	bcc .hl_scan
	ldx enemy_idx
	jmp check_line
.hl_yes
	ldx enemy_idx
	sec
	rts

; X = enemy. C=1 if tile DDA to player is clear.
; Solid 1..14 block; doors 15..16 need door_pos ≥ DOOR_LOS_MIN.
; 8.8 DDA: steps = max(|dx|,|dy|), step = (delta<<8)/steps from cell centers.
check_line
	stx enemy_idx
	lda playerx_h
	sec
	sbc enemy_xh,x
	sta ai_dx				; signed Δx tiles
	lda playery_h
	sec
	sbc enemy_yh,x
	sta ai_dy
	; abs dx → tmp0, abs dy → tmp1, steps = max
	lda ai_dx
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta tmp0
	lda ai_dy
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta tmp1
	cmp tmp0
	bcs +
	lda tmp0
+
	sta ai_steps
	; STA does not touch flags — Z may still be set from cmp when |dx|==|dy|
	lda ai_steps
	bne +
	jmp .cl_clear				; same tile
+
	; start at enemy cell center (8.8)
	ldx enemy_idx
	lda enemy_xh,x
	sta ai_xh
	lda enemy_yh,x
	sta ai_yh
	lda #$80
	sta ai_xl
	sta ai_yl
	; xstep = (dx << 8) / steps  (signed 8.8)
	lda ai_dx
	jsr .cl_mkstep
	lda tmp2
	sta ai_xsl
	lda tmp3
	sta ai_xsh
	lda ai_dy
	jsr .cl_mkstep
	lda tmp2
	sta ai_ysl
	lda tmp3
	sta ai_ysh
.cl_loop
	clc
	lda ai_xl
	adc ai_xsl
	sta ai_xl
	lda ai_xh
	adc ai_xsh
	sta ai_xh
	clc
	lda ai_yl
	adc ai_ysl
	sta ai_yl
	lda ai_yh
	adc ai_ysh
	sta ai_yh
	lda ai_xh
	sta tmp0
	lda ai_yh
	sta tmp1
	jsr .cl_cell
	bcc .cl_blocked
	dec ai_steps
	bne .cl_loop
.cl_clear
	ldx enemy_idx
	sec
	rts
.cl_blocked
	ldx enemy_idx
	clc
	rts

; A = signed tile delta → tmp2/tmp3 = signed 8.8 (delta<<8)/ai_steps
; Special-case 0 and |delta|==steps; else 16-iter bit divide (not subtract-loop).
.cl_mkstep
	sta tmp4				; keep sign
	bpl +
	eor #$ff
	clc
	adc #1
+
	beq .cl_mkz				; 0 → 0
	cmp ai_steps
	beq .cl_mkone				; |delta|==steps → ±1.0
	; dividend |delta|<<8 in tmp0:tmp1 (lo:hi), rem in tmp2
	sta tmp1
	lda #0
	sta tmp0
	sta tmp2
	ldx #16
.cl_bd
	asl tmp0
	rol tmp1
	rol tmp2
	lda tmp2
	cmp ai_steps
	bcc .cl_bdn
	sbc ai_steps
	sta tmp2
	inc tmp0				; set quot bit just shifted in
.cl_bdn
	dex
	bne .cl_bd
	; quot lo:hi in tmp0:tmp1 → tmp2:tmp3
	lda tmp0
	sta tmp2
	lda tmp1
	sta tmp3
	jmp .cl_mksign
.cl_mkz
	sta tmp2
	sta tmp3
	rts
.cl_mkone
	lda #0
	sta tmp2
	lda #1
	sta tmp3
.cl_mksign
	lda tmp4
	bpl .cl_mkok
	sec
	lda #0
	sbc tmp2
	sta tmp2
	lda #0
	sbc tmp3
	sta tmp3
.cl_mkok
	rts

; (tmp0,tmp1) cell — C=1 pass, C=0 blocked. Destination always ok.
.cl_cell
	lda tmp0
	cmp playerx_h
	bne +
	lda tmp1
	cmp playery_h
	beq .clc_ok
+
	; tile = MAP + y*64 + x (inline map_to_tile)
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
	ldy #0
	lda (tile_l),y
	cmp #1
	bcc .clc_ok			; 0 = empty
	cmp #15
	bcc .clc_wall			; 1..14 solid
	cmp #17
	bcs .clc_ok			; ≥17 floor
	lda tmp0
	sta mapx
	lda tmp1
	sta mapy
	jsr door_pos_at
	cmp #DOOR_LOS_MIN
	bcc .clc_wall
.clc_ok
	sec
	rts
.clc_wall
	clc
	rts

; X = enemy → tmp1 = Chebyshev tile dist, tmp0 = |dx|
enemy_tile_dist
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
	sta tmp1
	rts

; X = enemy — enter combat chase
first_sighting
	stx enemy_idx
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_PHASE_B)	; drop ambush
	ora #EF_FIRSTATTACK
	sta enemy_flags,x
	lda #ES_CHASE
	sta enemy_state,x
	lda #0
	sta enemy_state_t,x
	lda enemy_type,x
	cmp #ET_DOG
	bne .fs_halt
	lda #SOUND_DOGBARK
	jmp play_sound
.fs_halt
	lda #SOUND_HALT
	jmp play_sound

; ---------------------------------------------------------------------------
; Chase: path + CHASE_SPEED move (shoot / dodge face via enemy_los_rr)
; ---------------------------------------------------------------------------
enemy_chase_one
	stx enemy_idx
	lda enemy_flags,x
	and #EF_DODGE_FACE
	beq .ec_was
	; RR set dodge facing last frame — walk it, then clear
	lda enemy_flags,x
	and #$ff-EF_DODGE_FACE
	sta enemy_flags,x
	jmp .ec_domove
.ec_was
	; still walking last frame → keep facing (skip SelectChaseDir probes)
	lda enemy_flags,x
	and #EF_MOVING
	bne .ec_domove
.ec_pick
	jsr select_chase_dir
.ec_domove
	ldx enemy_idx
	; move like patrol at chase speed
	lda #1
	sta probe_doors_pass
	lda enemy_flags,x
	and #(EF_ACTIVE | EF_PHASE_B | EF_FIRSTATTACK | EF_SHOT_DONE)
	sta enemy_flags,x
	lda #0
	sta move_dx_l
	sta move_dx_h
	sta move_dy_l
	sta move_dy_h
	lda enemy_facing,x
	tay
	lda enemy_face_ang,y
	sta tmp4
	lda enemy_type,x
	cmp #ET_DOG
	bne .ec_humspd
	lda #DOG_CHASE_SPEED
	bne .ec_spd
.ec_humspd
	lda #CHASE_SPEED
.ec_spd
	sta vel_ms
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
	bne .ec_y
	ldx enemy_idx
	lda tmp2
	sta enemy_xl,x
	lda tmp3
	sta enemy_xh,x
	lda enemy_flags,x
	ora #EF_MOVING
	sta enemy_flags,x
.ec_y
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
	bne .ec_door
	ldx enemy_idx
	lda tmp2
	sta enemy_yl,x
	lda tmp3
	sta enemy_yh,x
	lda enemy_flags,x
	ora #EF_MOVING
	sta enemy_flags,x
.ec_door
	ldx enemy_idx
	lda enemy_flags,x
	and #EF_MOVING
	beq .ec_out				; no step → skip push_walls
	jsr enemy_push_walls
	ldx enemy_idx
	lda enemy_xh,x
	sta mapx
	sta tmp0
	lda enemy_yh,x
	sta mapy
	sta tmp1
	jsr door_is_door_xy
	beq .ec_out
	jsr try_open_door
.ec_out
	lda #0
	sta probe_doors_pass
	ldx enemy_idx
	rts

; Try walk into neighbor tile for facing A. Z=1 if ok.
enemy_try_face
	sta tmp5
	tay
	ldx enemy_idx
	clc
	lda enemy_xh,x
	adc .etf_dx,y
	sta mapx
	clc
	lda enemy_yh,x
	adc .etf_dy,y
	sta mapy
	lda #1
	sta probe_doors_pass
	jsr probe_solid
	php
	lda #0
	sta probe_doors_pass
	plp
	rts
; N NE E SE S SW W NW (signed tile deltas)
.etf_dx
	!byte 0, 1, 1, 1, 0, $ff, $ff, $ff
.etf_dy
	!byte $ff, $ff, 0, 1, 1, 1, 0, $ff

; Wolf SelectDodgeDir — cardinal zigzag toward player
select_dodge_dir
	ldx enemy_idx
	lda enemy_flags,x
	and #EF_FIRSTATTACK
	beq .sdd_turn
	lda #$ff				; nodir turnaround
	sta ai_turn
	lda enemy_flags,x
	and #$ff-EF_FIRSTATTACK
	sta enemy_flags,x
	jmp .sdd_dlt
.sdd_turn
	lda enemy_facing,x
	tay
	lda enemy_opp_face,y
	sta ai_turn
.sdd_dlt
	ldx enemy_idx
	lda playerx_h
	sec
	sbc enemy_xh,x
	sta tmp2				; dx
	lda playery_h
	sec
	sbc enemy_yh,x
	sta tmp3				; dy
	; dirtry: [0]=towardx [1]=towardy [2]=awayx [3]=awayy
	lda tmp2
	beq .sdd_nox
	bmi .sdd_wx
	lda #2					; E
	sta ai_dirtry
	lda #6					; W
	sta ai_dirtry+2
	jmp .sdd_y
.sdd_wx
	lda #6
	sta ai_dirtry
	lda #2
	sta ai_dirtry+2
	jmp .sdd_y
.sdd_nox
	lda #$ff
	sta ai_dirtry
	sta ai_dirtry+2
.sdd_y
	lda tmp3
	beq .sdd_noy
	bmi .sdd_ny
	lda #4					; S
	sta ai_dirtry+1
	lda #0					; N
	sta ai_dirtry+3
	jmp .sdd_abs
.sdd_ny
	lda #0
	sta ai_dirtry+1
	lda #4
	sta ai_dirtry+3
	jmp .sdd_abs
.sdd_noy
	lda #$ff
	sta ai_dirtry+1
	sta ai_dirtry+3
.sdd_abs
	; abs dx/dy
	lda tmp2
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta tmp0
	lda tmp3
	bpl +
	eor #$ff
	clc
	adc #1
+
	cmp tmp0
	bcc .sdd_rnd			; |dy| <= |dx| — no axis swap
	; swap toward pair and away pair
	lda ai_dirtry
	sta tmp4
	lda ai_dirtry+1
	sta ai_dirtry
	lda tmp4
	sta ai_dirtry+1
	lda ai_dirtry+2
	sta tmp4
	lda ai_dirtry+3
	sta ai_dirtry+2
	lda tmp4
	sta ai_dirtry+3
.sdd_rnd
	jsr rnd8
	bmi .sdd_try			; <128 keep
	lda ai_dirtry
	sta tmp4
	lda ai_dirtry+1
	sta ai_dirtry
	lda tmp4
	sta ai_dirtry+1
	lda ai_dirtry+2
	sta tmp4
	lda ai_dirtry+3
	sta ai_dirtry+2
	lda tmp4
	sta ai_dirtry+3
.sdd_try
	lda #0
	sta tmp4
.sdd_lp
	ldx tmp4
	lda ai_dirtry,x
	cmp #$ff
	beq .sdd_n
	cmp ai_turn
	beq .sdd_n
	jsr enemy_try_face
	bne .sdd_n
	; ok — commit
	ldx enemy_idx
	lda tmp5
	sta enemy_facing,x
	rts
.sdd_n
	inc tmp4
	lda tmp4
	cmp #4
	bcc .sdd_lp
	; last resort: turnaround
	lda ai_turn
	cmp #$ff
	beq .sdd_rts
	jsr enemy_try_face
	bne .sdd_rts
	ldx enemy_idx
	lda tmp5
	sta enemy_facing,x
.sdd_rts
	rts

; Wolf SelectChaseDir
select_chase_dir
	ldx enemy_idx
	lda enemy_facing,x
	sta ai_old
	tay
	lda enemy_opp_face,y
	sta ai_turn
	lda playerx_h
	sec
	sbc enemy_xh,x
	sta tmp2
	lda playery_h
	sec
	sbc enemy_yh,x
	sta tmp3
	lda #$ff
	sta ai_dirtry
	sta ai_dirtry+1
	lda tmp2
	beq +
	bmi .scd_w
	lda #2					; E
	sta ai_dirtry
	jmp +
.scd_w
	lda #6					; W
	sta ai_dirtry
+
	lda tmp3
	beq +
	bmi .scd_n
	lda #4					; S
	sta ai_dirtry+1
	jmp +
.scd_n
	lda #0					; N
	sta ai_dirtry+1
+
	; if |dy| > |dx| swap
	lda tmp2
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta tmp0
	lda tmp3
	bpl +
	eor #$ff
	clc
	adc #1
+
	cmp tmp0
	bcc +
	beq +
	lda ai_dirtry
	sta tmp4
	lda ai_dirtry+1
	sta ai_dirtry
	lda tmp4
	sta ai_dirtry+1
+
	lda ai_dirtry
	cmp ai_turn
	bne +
	lda #$ff
	sta ai_dirtry
+
	lda ai_dirtry+1
	cmp ai_turn
	bne +
	lda #$ff
	sta ai_dirtry+1
+
	lda ai_dirtry
	cmp #$ff
	beq .scd_d2
	jsr enemy_try_face
	bne .scd_d2
	ldx enemy_idx
	lda tmp5
	sta enemy_facing,x
	rts
.scd_d2
	lda ai_dirtry+1
	cmp #$ff
	beq .scd_old
	jsr enemy_try_face
	bne .scd_old
	ldx enemy_idx
	lda tmp5
	sta enemy_facing,x
	rts
.scd_old
	lda ai_old
	cmp #$ff
	beq .scd_sweep
	jsr enemy_try_face
	bne .scd_sweep
	ldx enemy_idx
	lda tmp5
	sta enemy_facing,x
	rts
.scd_sweep
	jsr rnd8
	bmi .scd_fw
	lda #6					; W → … → N (cardinals)
	sta tmp4
.scd_bwl
	lda tmp4
	cmp ai_turn
	beq +
	jsr enemy_try_face
	bne +
	ldx enemy_idx
	lda tmp5
	sta enemy_facing,x
	rts
+
	lda tmp4
	sec
	sbc #2
	sta tmp4
	bcs .scd_bwl
	jmp .scd_rev
.scd_fw
	lda #0
	sta tmp4
.scd_fwl
	lda tmp4
	cmp ai_turn
	beq +
	jsr enemy_try_face
	bne +
	ldx enemy_idx
	lda tmp5
	sta enemy_facing,x
	rts
+
	lda tmp4
	clc
	adc #2
	sta tmp4
	cmp #8
	bcc .scd_fwl
.scd_rev
	; last resort: turnaround (same as SelectDodgeDir)
	lda ai_turn
	jsr enemy_try_face
	bne .scd_rts
	ldx enemy_idx
	lda tmp5
	sta enemy_facing,x
.scd_rts
	rts

; X set via enemy_idx — Wolf T_Shoot → take_damage
enemy_shoot
	ldx enemy_idx
	jsr has_los_to_player
	bcc .es_rts
	lda #SOUND_NAZIFIRE
	jsr play_sound
	jsr enemy_tile_dist
	lda tmp1
	sta ai_dist
	cmp #THINK_DIST
	bcs .es_rts
	; hitchance: in col_enemy → 256-dist*16 else 256-dist*8
	stx tmp4
	lda #0
	sta tmp5
	ldx #COL_FIRST
.es_vis
	lda col_enemy,x
	cmp tmp4
	bne +
	lda #1
	sta tmp5
	bne .es_hc
+
	inx
	cpx #COL_LIMIT
	bcc .es_vis
.es_hc
	ldx enemy_idx
	lda ai_dist
	ldy tmp5
	beq .es_hid
	asl
	asl
	asl
	asl					; dist*16
	jmp .es_sub
.es_hid
	asl
	asl
	asl					; dist*8
.es_sub
	sta tmp0
	lda #0
	sec
	sbc tmp0				; hitchance = 256 - dist*k
	sta tmp0
	jsr rnd8
	cmp tmp0
	bcs .es_rts			; miss
	lda ai_dist
	cmp #2
	bcs .es_d4
	jsr rnd8
	lsr
	lsr
	jmp .es_dmg
.es_d4
	lda ai_dist
	cmp #4
	bcs .es_dfar
	jsr rnd8
	lsr
	lsr
	lsr
	jmp .es_dmg
.es_dfar
	jsr rnd8
	lsr
	lsr
	lsr
	lsr
.es_dmg
	jsr take_damage
.es_rts
	ldx enemy_idx
	rts

