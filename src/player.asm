; WASD only (no joystick — floating CIA bits cause phantom input)
!zone player

WALL_MARGIN = $40				; 1/4 tile keep-out from solid faces
WALL_MARGIN_HI = $100 - WALL_MARGIN	; $C0 — max frac when east/south neighbor solid
T_PLAYER	= 48				; +0..3 = N,E,S,W

; Map tiles 48..51 → player tile + facing (0=E,64=N,128=W,192=S)
find_spawn
	lda #<MAP
	sta tmp0
	lda #>MAP
	sta tmp1
	lda #0
	sta tmp2				; x
	sta tmp3				; y
.fs_loop
	ldy #0
	lda (tmp0),y
	cmp #T_PLAYER
	bcc .fs_next
	cmp #T_PLAYER + 4
	bcs .fs_next
	sec
	sbc #T_PLAYER
	tax
	lda .spawn_ang,x
	sta playera
	lda tmp2
	sta playerx_h
	lda tmp3
	sta playery_h
	lda #$80
	sta playerx_l
	sta playery_l
	rts
.fs_next
	inc tmp0
	bne +
	inc tmp1
+
	inc tmp2
	lda tmp2
	cmp #64
	bne .fs_loop
	lda #0
	sta tmp2
	inc tmp3
	lda tmp3
	cmp #64
	bne .fs_loop
	; no marker: center-ish facing east
	lda #32
	sta playerx_h
	sta playery_h
	lda #$80
	sta playerx_l
	sta playery_l
	lda #0
	sta playera
	rts

.spawn_ang
	!byte 64				; N
	!byte 0					; E
	!byte 192				; S
	!byte 128				; W


; Hold-ms turn + wish from IRQ; apply move_dx/dy with wall slide
player_move
	jsr read_input
	lda move_dx_l
	ora move_dx_h
	ora move_dy_l
	ora move_dy_h
	bne .apply
	rts

.apply
	; X axis
	clc
	lda playerx_l
	adc move_dx_l
	sta tmp2
	lda playerx_h
	adc move_dx_h
	sta tmp3
	lda tmp3
	sta mapx
	lda playery_h
	sta mapy
	jsr probe_solid
	beq .x_ok
	jsr try_open_door
	jmp .try_y
.x_ok
	lda tmp2
	sta playerx_l
	lda tmp3
	sta playerx_h
.try_y
	clc
	lda playery_l
	adc move_dy_l
	sta tmp2
	lda playery_h
	adc move_dy_h
	sta tmp3
	lda playerx_h
	sta mapx
	lda tmp3
	sta mapy
	jsr probe_solid
	beq .y_ok
	jsr try_open_door
	jmp .push
.y_ok
	lda tmp2
	sta playery_l
	lda tmp3
	sta playery_h
.push
	jmp push_walls

; Keep frac ≥ WALL_MARGIN from each adjacent solid face (SquareDoom push_walls).
; tmp4/5 = player tile (probe_solid clobbers tmp0/1).
push_walls
	lda playerx_h
	sta tmp4
	lda playery_h
	sta tmp5

	; West: mapx-1
	lda tmp4
	sec
	sbc #1
	sta mapx
	lda tmp5
	sta mapy
	jsr probe_solid
	beq .pw_east
	lda playerx_l
	cmp #WALL_MARGIN
	bcs .pw_east
	lda #WALL_MARGIN
	sta playerx_l

.pw_east
	lda tmp4
	clc
	adc #1
	sta mapx
	lda tmp5
	sta mapy
	jsr probe_solid
	beq .pw_north
	lda playerx_l
	cmp #WALL_MARGIN_HI + 1		; > $C0 → snap (exact $C0 ok)
	bcc .pw_north
	lda #WALL_MARGIN_HI
	sta playerx_l

.pw_north
	; mapy-1 (north; Y grows south)
	lda tmp4
	sta mapx
	lda tmp5
	sec
	sbc #1
	sta mapy
	jsr probe_solid
	beq .pw_south
	lda playery_l
	cmp #WALL_MARGIN
	bcs .pw_south
	lda #WALL_MARGIN
	sta playery_l

.pw_south
	lda tmp4
	sta mapx
	lda tmp5
	clc
	adc #1
	sta mapy
	jsr probe_solid
	beq .pw_done
	lda playery_l
	cmp #WALL_MARGIN_HI + 1		; > $C0 → snap (exact $C0 ok)
	bcc .pw_done
	lda #WALL_MARGIN_HI
	sta playery_l
.pw_done
	rts

probe_solid
	lda mapx
	sta tmp0
	lda mapy
	sta tmp1
	jsr map_to_tile
	ldy #0
	lda (tile_l),y
	cmp #17				; solid walls + doors < 17
	bcs .clear
	cmp #15				; unlocked door
	bne .solid
	lda probe_doors_pass
	bne .clear			; enemies may walk door tiles
.solid
	lda #1
	rts
.clear
	lda #0
	rts

; A = damage — subtract from player_hp, floor at 0 (Wolf TakeDamage lite)
take_damage
	ldx player_dead
	bne .td_rts
	sta tmp0
	lda player_hp
	sec
	sbc tmp0
	bcs +
	lda #0
+
	sta player_hp
	lda #UI_DIRTY_HP | UI_DIRTY_FACE
	ora ui_dirty
	sta ui_dirty
	lda player_hp
	bne .td_hurt
	lda #1
	sta player_dead
	lda #<1500
	sta death_ms_l
	lda #>1500
	sta death_ms_h
	lda #SOUND_PLAYERDEATH
	jmp play_sound
.td_hurt
	lda #SOUND_TAKEDAMAGE
	jmp play_sound
.td_rts
	rts

; Once per game — lives/score/ammo/keys/weapons
player_init_game
	lda #START_LIVES
	sta player_lives
	lda #0
	sta player_score_l
	sta player_score_h
	sta player_keys
	sta player_dead
	sta death_ms_l
	sta death_ms_h
	sta level_want
	lda #START_AMMO
	sta player_ammo
	lda #HP_MAX
	sta player_hp
	lda #$03				; knife + pistol
	sta owned_weapons
	lda #UI_DIRTY_ALL
	sta ui_dirty
	rts

; After death restart — full HP, clear keys; keep ammo/weapons/score/lives
player_init_level
	lda #0
	sta player_dead
	sta death_ms_l
	sta death_ms_h
	sta player_keys
	sta level_want
	lda #HP_MAX
	sta player_hp
	lda #UI_DIRTY_ALL
	sta ui_dirty
	rts

; Countdown while dead; then lives-- and request restart
player_death_tick
	lda death_ms_l
	ora death_ms_h
	beq .pdt_go
	sec
	lda death_ms_l
	sbc dt_ms
	sta death_ms_l
	lda death_ms_h
	sbc #0
	sta death_ms_h
	bcs .pdt_rts
	lda #0
	sta death_ms_l
	sta death_ms_h
.pdt_go
	lda player_lives
	beq .pdt_newgame
	dec player_lives
	lda #UI_DIRTY_LIVES
	ora ui_dirty
	sta ui_dirty
	lda #1				; restart
	sta level_want
.pdt_rts
	rts
.pdt_newgame
	lda #3				; out of lives — fresh game
	sta level_want
	rts

; Walk-on exit tile 144
player_check_exit
	lda playerx_h
	sta tmp0
	lda playery_h
	sta tmp1
	jsr map_to_tile
	ldy #0
	lda (tile_l),y
	cmp #T_EXIT
	bne .pce_rts
	lda #2				; next level
	sta level_want
.pce_rts
	rts

; level_want: 1=restart 2=next 3=new game — disk reload + re-init
; Player init after successful load so a failed LoadLevel can restore VIC.
handle_level_want
	lda level_want
	pha					; 1=restart 2=next 3=new game
	cmp #2
	bne .hlw_chknew
	jsr advance_level			; needs new level_num before FormatDosName
	jmp .hlw_load
.hlw_chknew
	cmp #3
	bne .hlw_load
	lda #1					; out of lives — back to level 1
	sta level_num
.hlw_load
	lda #0
	sta level_want
	jsr restart_level
	bcc .hlw_ok
	; Load failed — restore VIC and keep playing
	pla
	cmp #1
	bne .hlw_fail_vis
	inc player_lives			; refund death_tick decrement
	lda #UI_DIRTY_LIVES
	ora ui_dirty
	sta ui_dirty
.hlw_fail_vis
	sei
	lda #$35
	sta $01
	jsr init_vic
	lda #$02				; red border = load error
	sta $d020
	lda #$34
	sta $01
	cli
	rts
.hlw_ok
	pla
	cmp #2
	beq .hlw_done				; advance_level already ran
	cmp #3
	bne .hlw_restart
	jsr player_init_game			; fresh game — lives/score/ammo/weapons
	jsr init_weapon				; ownership reset — back to pistol
	jmp .hlw_done
.hlw_restart
	jsr player_init_level
.hlw_done
	lda #0					; successful restart: restore black border
	sta $d020
	lda #$34
	sta $01
	cli
	rts

; Bump episode map index; clear keys; keep HP/ammo/weapons
advance_level
	ldx level_num
	inx
	cpx #LEVEL_MAX + 1
	bcc .al_set
	ldx #1
.al_set
	stx level_num
	lda #0
	sta player_keys
	sta player_dead
	sta death_ms_l
	sta death_ms_h
	lda #UI_DIRTY_ALL
	sta ui_dirty
	rts
