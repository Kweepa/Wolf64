; Score /100 + HUD draw + extra-life. Linked at SCORE_CODE ($64B0).
; Hidden: row 3 cols 30–39 + row 4 must keep screen/colour 0.
!zone score
!source "../generated/src/ui_attr.inc"

; ET_GUARD, ET_SS, ET_DOG, ET_HANS
kill_pts
	!byte 1, 5, 2, 50

; X = enemy (clobbered; restored from enemy_idx)
score_add_kill
	ldy enemy_type,x
	lda kill_pts,y
	jsr score_add
	ldx enemy_idx
	rts

; A = frame. Extra life (full HP, +25 ammo, +1 life) or treasure points.
item_try_oneup
	cmp #IF_ONEUP
	beq item_take_oneup
	jmp item_try_treasure

; Full HP, +ONEUP_AMMO_AMT ammo, +1 life (cap LIVES_MAX). C=1 collected.
item_take_oneup
	lda #HP_MAX
	sta player_hp
	clc
	lda player_ammo
	adc #ONEUP_AMMO_AMT
	bcs .ito_sat
	cmp #AMMO_MAX + 1
	bcc .ito_ammo
.ito_sat
	lda #AMMO_MAX
.ito_ammo
	sta player_ammo
	lda player_lives
	cmp #LIVES_MAX
	bcs .ito_ui
	inc player_lives
.ito_ui
	lda #UI_DIRTY_HP | UI_DIRTY_FACE | UI_DIRTY_AMMO | UI_DIRTY_LIVES
	ora ui_dirty
	sta ui_dirty
	lda #SOUND_BONUS1
	jsr play_sound
	sec
	rts

; A = units (score / 100). Sets UI_DIRTY_SCORE; extra life every SCORE_1UP.
score_add
	clc
	adc player_score_l
	sta player_score_l
	bcc +
	inc player_score_h
+
	lda #UI_DIRTY_SCORE
	ora ui_dirty
	sta ui_dirty
	lda player_score_l
	cmp score_1up_l
	lda player_score_h
	sbc score_1up_h
	bcc .sa_rts
	inc player_lives
	lda #UI_DIRTY_LIVES
	ora ui_dirty
	sta ui_dirty
	clc
	lda score_1up_l
	adc #<SCORE_1UP
	sta score_1up_l
	lda score_1up_h
	adc #>SCORE_1UP
	sta score_1up_h
.sa_rts
	rts

; I/O in, blit score digits, I/O out. Clears UI_DIRTY_SCORE only.
draw_ui
	lda #$35
	sta $01
	jsr ui_score
	lda #$34
	sta $01
	lda ui_dirty
	and #$FF - UI_DIRTY_SCORE
	sta ui_dirty
	rts

; Level-up: add then paint immediately (jingle freeze never hits ui_update).
score_add_hud_and_redraw
	jsr score_add
	jmp draw_ui

; 16-bit units → 4 digits at UI_COL_SCORE, then two static 0s. Uses ui_dig.
ui_score
	lda player_score_l
	sta pp_tmp_l
	lda player_score_h
	sta pp_tmp_h
	lda #4
	sta pp_dig_t
	sta pp_dig_h
.us_spl
	lda #0
	sta tmp0				; quot lo
	sta tmp1				; quot hi
.us_d
	lda pp_tmp_h
	bne .us_sub
	lda pp_tmp_l
	cmp #10
	bcc .us_r
.us_sub
	sec
	lda pp_tmp_l
	sbc #10
	sta pp_tmp_l
	lda pp_tmp_h
	sbc #0
	sta pp_tmp_h
	inc tmp0
	bne .us_d
	inc tmp1
	bne .us_d
.us_r
	lda pp_tmp_l
	pha
	lda tmp0
	sta pp_tmp_l
	lda tmp1
	sta pp_tmp_h
	dec pp_dig_t
	bne .us_spl
	ldx #UI_COL_SCORE
.us_out
	pla
	jsr ui_dig
	inx
	dec pp_dig_h
	bne .us_out
	lda #0
	jsr ui_dig
	inx
	lda #0
	jmp ui_dig
