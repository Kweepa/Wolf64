; Sideways-sliding doors (Wolf3D-style midplane; one surface per column)
!zone doors

NUM_DOOR_SLOTS	= 8				; player + concurrent patrol doors
; dt_ms-driven: 255 pos steps × DOOR_STEP_MS ≈ 0.5s open/close
DOOR_STEP_MS	= 2				; door_pos ±1 when accum ≥ this
DOOR_HOLD_MS	= 2000				; fully open before auto-close
T_DOOR_MIN	= 15
T_DOOR_MAX	= 17				; inclusive
T_LOCKED_GOLD	= 16
T_LOCKED_SILVER	= 17
T_FLOOR		= 18
; T_PUSHWALL from mem.asm
TEX_DOOR	= 11
TEX_LOCKED_GOLD	= 0
TEX_LOCKED_SILVER = 12
TEX_JAMB	= 15
DS_FREE		= 0
DS_OPENING	= 1
DS_OPEN		= 2
DS_CLOSING	= 3
DO_MIDX		= 0				; plane at mid-X; hit on .adv_x
DO_MIDY		= 1				; plane at mid-Y; hit on .adv_y

; --- lookup / helpers -------------------------------------------------------

; Clear all door anim slots (level restart / fresh map)
doors_clear
	ldy #0
	lda #DS_FREE
.dc_lp
	sta door_state,y
	iny
	cpy #NUM_DOOR_SLOTS
	bcc .dc_lp
	rts

; A = open amount for (mapx,mapy); 0 if not in a slot (closed default)
; Clobbers: Y (not X)
door_pos_at
	ldy #0
.dpa_lp
	lda door_state,y
	beq .dpa_next
	lda door_x,y
	cmp mapx
	bne .dpa_next
	lda door_y,y
	cmp mapy
	bne .dpa_next
	lda door_pos,y
	rts
.dpa_next
	iny
	cpy #NUM_DOOR_SLOTS
	bcc .dpa_lp
	lda #0
	rts

; A = orient for (mapx,mapy): slot value or inferred
; Clobbers: tmp0/tmp1/tmp2/tmp3, tile_*, Y
door_orient_at
	ldy #0
.doa_lp
	lda door_state,y
	beq .doa_next
	lda door_x,y
	cmp mapx
	bne .doa_next
	lda door_y,y
	cmp mapy
	bne .doa_next
	lda door_orient,y
	rts
.doa_next
	iny
	cpy #NUM_DOOR_SLOTS
	bcc .doa_lp
	; fall through — infer from N/S walls
door_infer_orient
	; solids N and S → mid-X doorway; else mid-Y
	lda mapx
	sta tmp0
	lda mapy
	sec
	sbc #1
	sta tmp1
	jsr door_tile_at
	cmp #T_FLOOR
	bcs .dio_midy
	lda mapy
	clc
	adc #1
	sta tmp1
	jsr door_tile_at
	cmp #T_FLOOR
	bcs .dio_midy
	lda #DO_MIDX
	rts
.dio_midy
	lda #DO_MIDY
	rts

; A = door tile 15..17 → A = TEX_* (table indexed by tile)
door_tex_for_tile
	tax
	lda door_tex_tab - T_DOOR_MIN,x
	rts
door_tex_tab
	!byte TEX_DOOR, TEX_LOCKED_GOLD, TEX_LOCKED_SILVER

; tmp0=x tmp1=y → A = tile; clobbers tile_*
door_tile_at
	jsr map_to_tile
	ldy #0
	lda (tile_l),y
	rts

; tmp0=x tmp1=y → A≠0 if door tile or animating slot (open map=floor)
; Clobbers: tile_*, Y, tmp2
door_is_door_xy
	jsr door_tile_at
	cmp #T_DOOR_MIN
	bcc .dix_slots
	cmp #T_DOOR_MAX + 1
	bcs .dix_slots
	lda #1
	rts
.dix_slots
	ldy #0
.dix_lp
	lda door_state,y
	beq .dix_next
	lda door_x,y
	cmp tmp0
	bne .dix_next
	lda door_y,y
	cmp tmp1
	bne .dix_next
	lda #1
	rts
.dix_next
	iny
	cpy #NUM_DOOR_SLOTS
	bcc .dix_lp
	lda #0
	rts

; Jamb only on the face looking into the doorway (Wolf HitVert/HorizWall):
; X-hit → check (mapx - xstep, mapy); Y-hit → check (mapx, mapy - ystep).
; Clobbers: tmp0/tmp1/tmp2, tile_*, Y
door_jamb_check
	lda side
	bne .djc_y
	lda mapx
	sec
	sbc xstep
	sta tmp0
	lda mapy
	sta tmp1
	jmp .djc_test
.djc_y
	lda mapx
	sta tmp0
	lda mapy
	sec
	sbc ystep
	sta tmp1
.djc_test
	jsr door_is_door_xy
	beq .djc_rts
	lda #TEX_JAMB
	sta tex_id
.djc_rts
	rts

; Write A into map at door_x,y for slot Y
door_poke_map
	sta tmp2
	lda door_x,y
	sta tmp0
	lda door_y,y
	sta tmp1
	tya
	pha
	jsr map_to_tile
	pla
	tay
	tya
	pha
	ldy #0
	lda tmp2
	sta (tile_l),y
	pla
	tay
	rts

; --- open / update ----------------------------------------------------------

; mapx,mapy = cell bumped; pushwalls, elevators, then doors
try_open_door
	lda mapx
	sta tmp0
	lda mapy
	sta tmp1
	jsr door_tile_at
	cmp #T_PUSHWALL
	bne .tod_elev
	jmp try_push_wall
.tod_elev
	cmp #T_ELEVATOR
	bne .tod_door
	lda #2				; next level
	sta level_want
	rts
.tod_door
	cmp #T_DOOR_MIN
	bcc .tod_rts
	cmp #T_LOCKED_GOLD
	bcc .tod_open			; unlocked 15
	cmp #T_DOOR_MAX + 1
	bcs .tod_rts			; not a door
	sta tmp3				; 16 gold / 17 silver
	and #1
	tax
	lda .tod_keybit,x
	and player_keys
	beq .tod_rts
	lda tmp3
.tod_open
	sta tmp3				; saved door tile id
	; already in a slot?
	ldy #0
.tod_find
	lda door_state,y
	beq .tod_next
	lda door_x,y
	cmp mapx
	bne .tod_next
	lda door_y,y
	cmp mapy
	bne .tod_next
	; reopen / reverse close
	lda door_state,y
	cmp #DS_CLOSING
	bne .tod_hold
	lda #DS_OPENING
	sta door_state,y
	lda #SOUND_OPENDOOR
	jsr play_sound
	rts
.tod_hold
	cmp #DS_OPEN
	bne .tod_rts
	lda #<DOOR_HOLD_MS
	sta door_tic_l,y
	lda #>DOOR_HOLD_MS
	sta door_tic_h,y
	rts
.tod_next
	iny
	cpy #NUM_DOOR_SLOTS
	bcc .tod_find
	; claim free slot — fall through to existing open path
	ldy #0
.tod_free
	lda door_state,y
	beq .tod_claim
	iny
	cpy #NUM_DOOR_SLOTS
	bcc .tod_free
.tod_rts
	rts
.tod_keybit
	!byte KEY_GOLD, KEY_SILVER
.tod_claim
	lda mapx
	sta door_x,y
	lda mapy
	sta door_y,y
	lda tmp3
	sta door_tile,y
	lda #0
	sta door_pos,y
	sta door_tic_l,y			; motion ms accum
	sta door_tic_h,y
	lda #DS_OPENING
	sta door_state,y
	tya
	pha
	jsr door_infer_orient
	sta tmp2
	pla
	tay
	lda tmp2
	sta door_orient,y
	lda #SOUND_OPENDOOR
	jsr play_sound
	rts

doors_update
	ldy #0
.du_lp
	lda door_state,y
	beq .du_next
	cmp #DS_OPENING
	bne +
	jmp .du_opening
+
	cmp #DS_OPEN
	bne +
	jmp .du_open
+
	cmp #DS_CLOSING
	bne .du_next
	jmp .du_closing
.du_next
	iny
	cpy #NUM_DOOR_SLOTS
	bcc .du_lp
	rts

; Opening/closing: add dt_ms once, then spend STEP_MS units (do not re-add)
.du_opening
	jsr .du_add_dt
.du_open_step
	jsr .du_try_step
	bcc .du_next_jmp
	clc
	lda door_pos,y
	adc #1
	bcc +
	lda #$ff
+
	sta door_pos,y
	cmp #$ff
	bne .du_open_step
	lda #T_FLOOR
	jsr door_poke_map
	lda #DS_OPEN
	sta door_state,y
	lda #<DOOR_HOLD_MS
	sta door_tic_l,y
	lda #>DOOR_HOLD_MS
	sta door_tic_h,y
.du_next_jmp
	jmp .du_next

.du_open
	jsr .du_blocker_in
	bne .du_open_timer			; not in doorway → countdown
	; player/enemy in doorway — keep open, refresh hold
	lda #<DOOR_HOLD_MS
	sta door_tic_l,y
	lda #>DOOR_HOLD_MS
	sta door_tic_h,y
	jmp .du_next
.du_open_timer
	; 16-bit hold countdown in ms
	lda door_tic_l,y
	ora door_tic_h,y
	beq .du_start_close
	sec
	lda door_tic_l,y
	sbc dt_ms
	sta door_tic_l,y
	lda door_tic_h,y
	sbc #0
	sta door_tic_h,y
	bcc .du_start_close			; underflow → close now
	jmp .du_next
.du_start_close
	jsr .du_blocker_in
	bne +					; clear → close
	jmp .du_next				; still blocked — wait
+
	lda door_tile,y
	jsr door_poke_map			; put door id back for DDA while closing
	lda #0
	sta door_tic_l,y
	sta door_tic_h,y
	lda #DS_CLOSING
	sta door_state,y
	lda #SOUND_CLOSEDOOR
	jsr play_sound
	jmp .du_next

.du_closing
	jsr .du_blocker_in
	bne .du_closing_go			; clear → keep closing
	lda #DS_OPENING			; blocked — reopen
	sta door_state,y
	lda #SOUND_OPENDOOR
	jsr play_sound
	jmp .du_next
.du_closing_go
	jsr .du_add_dt
.du_close_step
	jsr .du_try_step
	bcc .du_next_jmp
	lda door_pos,y
	sec
	sbc #1
	bcs +
	lda #0
+
	sta door_pos,y
	bne .du_close_step
	lda door_tile,y
	jsr door_poke_map
	lda #DS_FREE
	sta door_state,y
	jmp .du_next

; Z=1 if player or any active enemy is on door_x/y for slot Y.
; Preserves Y; clobbers A and uses door_savex for X.
.du_blocker_in
	lda door_x,y
	cmp playerx_h
	bne .du_bi_en
	lda door_y,y
	cmp playery_h
	beq .du_bi_yes			; Z=1
.du_bi_en
	stx door_savex
	ldx #0
.du_bi_lp
	cpx enemy_count
	bcs .du_bi_no
	lda enemy_flags,x
	and #$01				; EF_ACTIVE
	beq .du_bi_nx
	lda enemy_xh,x
	cmp door_x,y
	bne .du_bi_nx
	lda enemy_yh,x
	cmp door_y,y
	bne .du_bi_nx
	ldx door_savex
	lda #0					; Z=1 (ldx may clear Z)
	rts
.du_bi_nx
	inx
	bne .du_bi_lp
.du_bi_no
	ldx door_savex
	lda #1					; Z=0
	rts
.du_bi_yes
	rts					; Z=1 from player cmp

; door_tic += dt_ms
.du_add_dt
	clc
	lda door_tic_l,y
	adc dt_ms
	sta door_tic_l,y
	lda door_tic_h,y
	adc #0
	sta door_tic_h,y
	rts

; If door_tic ≥ DOOR_STEP_MS, subtract and C=1; else C=0
.du_try_step
	lda door_tic_l,y
	cmp #<DOOR_STEP_MS
	lda door_tic_h,y
	sbc #>DOOR_STEP_MS
	bcc .du_ts_no
	sec
	lda door_tic_l,y
	sbc #<DOOR_STEP_MS
	sta door_tic_l,y
	lda door_tic_h,y
	sbc #>DOOR_STEP_MS
	sta door_tic_h,y
	sec
	rts
.du_ts_no
	clc
	rts

; --- DDA midplane hit tests -------------------------------------------------
; On entry: (mapx,mapy) door cell, tile_* valid, sdx/sdy at near face.
; Out: C=1 hit (tex_id, texx, side, wallz set); C=0 continue past.
; Preserves X (DDA step budget). Clobbers Y, tmp*, aux*, tile_* (restored).

door_try_x
	stx door_savex
	lda tile_l
	sta door_savetl
	lda tile_h
	sta door_saveth
	jsr door_orient_at
	cmp #DO_MIDX
	bne .dtx_pass
	; wallz = sdx + ddx/2
	lda ddx_h
	lsr
	sta tmp1
	lda ddx_l
	ror
	clc
	adc sdx_l
	sta wallz_l
	lda tmp1
	adc sdx_h
	sta wallz_h
	bcs .dtx_pass
	; Wolf passvert: next Y grid closer than midplane → jamb face first
	lda sdy_h
	cmp wallz_h
	bcc .dtx_pass
	bne .dtx_along
	lda sdy_l
	cmp wallz_l
	bcc .dtx_pass
.dtx_along
	; along at midplane (same as hit_wall side=0 U before >>4)
	lda wallz_l
	sta aux_l
	lda wallz_h
	sta aux_h
	ldy dyindex
	lda fixcos,y
	jsr mul_16x8
	ldx ystep
	ldy fracy
	jsr door_u_combine			; A = along_frac
	sta tmp2
	jsr door_pos_at
	sta tmp3
	lda tmp2
	cmp tmp3
	bcc .dtx_pass
	sec
	sbc tmp3
	lsr
	lsr
	lsr
	lsr
	and #15
	sta texx
	lda door_savetl
	sta tile_l
	lda door_saveth
	sta tile_h
	ldy #0
	lda (tile_l),y
	jsr door_tex_for_tile
	sta tex_id
	lda #0
	sta side
	ldx door_savex
	sec
	rts
.dtx_pass
	lda door_savetl
	sta tile_l
	lda door_saveth
	sta tile_h
	ldx door_savex
	clc
	rts

door_try_y
	stx door_savex
	lda tile_l
	sta door_savetl
	lda tile_h
	sta door_saveth
	jsr door_orient_at
	cmp #DO_MIDY
	bne .dty_pass
	lda ddy_h
	lsr
	sta tmp1
	lda ddy_l
	ror
	clc
	adc sdy_l
	sta wallz_l
	lda tmp1
	adc sdy_h
	sta wallz_h
	bcs .dty_pass
	; Wolf passhoriz: next X grid closer than midplane → jamb face first
	lda sdx_h
	cmp wallz_h
	bcc .dty_pass
	bne .dty_along
	lda sdx_l
	cmp wallz_l
	bcc .dty_pass
.dty_along
	lda wallz_l
	sta aux_l
	lda wallz_h
	sta aux_h
	ldy dxindex
	lda fixcos,y
	jsr mul_16x8
	ldx xstep
	ldy fracx
	jsr door_u_combine
	sta tmp2
	jsr door_pos_at
	sta tmp3
	lda tmp2
	cmp tmp3
	bcc .dty_pass
	sec
	sbc tmp3
	lsr
	lsr
	lsr
	lsr
	and #15
	sta texx
	lda door_savetl
	sta tile_l
	lda door_saveth
	sta tile_h
	ldy #0
	lda (tile_l),y
	jsr door_tex_for_tile
	sta tex_id
	lda #1
	sta side
	ldx door_savex
	sec
	rts
.dty_pass
	lda door_savetl
	sta tile_l
	lda door_saveth
	sta tile_h
	ldx door_savex
	clc
	rts

; A = mul result; X = ±step sign; Y = player frac → A = along 0..255-ish
door_u_combine
	cpx #0
	bmi .duc_neg
	clc
	sty tmp0
	adc tmp0
	rts
.duc_neg
	sec
	sty tmp0
	sbc tmp0
	eor #$ff
	rts

; Finish door column: tex_id/texx/side/wallz set; fish-eye via wallz (midplane)
hit_door
	lda tex_id
	ldx col
	sta col_texid,x
	lda wallz_l
	sta aux_l
	lda wallz_h
	sta aux_h
	ldx col
	lda fishtab,x
	jsr mul_16x8
	sta wallz_l
	stx wallz_h
	ldx col
	lda wallz_l
	sta col_wallz_l,x
	lda wallz_h
	sta col_wallz_h,x
	jsr calc_half_h
	ldx col
	lda half_h
	sta col_half_h,x
	lda texx
	sta col_texx,x
	rts
