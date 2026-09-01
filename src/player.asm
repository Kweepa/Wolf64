; WASD / IJKL (stick is input.asm / joy_en — floating CIA bits if always polled)
!zone player

WALL_MARGIN = $40				; 1/4 tile keep-out (player, guard, SS)
WALL_MARGIN_WIDE = $66			; dogs/Hans ~0.4 tile (wide billboards)
SPRITE_Z_BIAS = $10				; vis_depth = perp − this (1/16 tile toward camera)
T_PLAYER	= 49				; +0..3 = N,E,S,W

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
	jmp .push
.y_ok
	lda tmp2
	sta playery_l
	lda tmp3
	sta playery_h
.push
	; Contact open (margin / this-step tile cross) then WALL_MARGIN push
	jmp player_bump_then_push

; A = keep-out frac. tmp2 = lo, tmp3 = $100−A; tmp4/5 = tile (probe_solid clobbers tmp0/1).
push_walls
	sta tmp2
	lda #0
	sec
	sbc tmp2
	sta tmp3
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
	cmp tmp2
	bcs .pw_east
	lda tmp2
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
	cmp tmp3
	beq .pw_north
	bcc .pw_north
	lda tmp3
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
	cmp tmp2
	bcs .pw_south
	lda tmp2
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
	cmp tmp3
	beq .pw_done
	bcc .pw_done
	lda tmp3
	sta playery_l
.pw_done
	rts

probe_solid
	lda mapx
	sta tmp0
	lda mapy
	sta tmp1
	jsr door_tile_at
	cmp #18				; solid walls + doors < 18
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

; Add clip grant to player_ammo (Daddy doubles); saturate at AMMO_MAX.
ammo_clip_amt
	lda #AMMO_CLIP_AMT
	ldy difficulty
	bne +
	asl
+
	clc
	adc player_ammo
	bcs .aca_sat
	cmp #AMMO_MAX + 1
	bcc .aca_ok
.aca_sat
	lda #AMMO_MAX
.aca_ok
	sta player_ammo
	rts

; A = damage — subtract from player_hp, floor at 0 (Wolf TakeDamage lite)
; Daddy (difficulty 0): points >>= 2. Queues one-frame red border.
take_damage
	ldx player_dead
	bne .td_rts
	ldx difficulty
	bne .td_sub
	lsr
	lsr
.td_sub
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
	lda #1
	sta hurt_flash
	lda #SOUND_TAKEDAMAGE
	jmp play_sound
.td_rts
	rts

; Red $d020 while dead, or for one frame after hurt. Call with $01=$35.
; hurt_flash: 1 = paint red (→2), 2 = restore black (→0). Idle leaves border alone.
player_border_tick
	lda player_dead
	bne .pbt_red
	lda hurt_flash
	beq .pbt_rts
	cmp #1
	bne .pbt_clear
	lda #2
	sta hurt_flash
.pbt_red
	lda #$02
	sta $d020
	rts
.pbt_clear
	lda #0
	sta hurt_flash
	sta $d020
.pbt_rts
	rts

; Once per game — lives then loadout; falls into player_init_level
player_init_game
	lda #START_LIVES
	sta player_lives
	lda #0
	sta player_score_l
	sta player_score_h
	lda #<SCORE_1UP
	sta score_1up_l
	lda #>SCORE_1UP
	sta score_1up_h
	; fall through — ammo + knife/pistol, then HP

; After death restart — default ammo/weapons + full HP; keep lives
player_init_life
	lda #START_AMMO
	ldx difficulty
	bne +
	asl					; Daddy: double start ammo
+
	sta player_ammo
	lda #$03				; knife + pistol
	sta owned_weapons
	; fall through — full HP, clear keys/death, dirty UI

player_init_level
	lda #0
	sta level_want
	lda #HP_MAX
	sta player_hp
	; fall through

; Clear keys/death flash; mark full UI dirty
player_reset_status
	lda #0
	sta player_keys
	sta player_dead
	sta death_ms_l
	sta death_ms_h
	sta hurt_flash
	lda #UI_DIRTY_ALL
	sta ui_dirty
	rts

; Countdown while dead; lives left → restart level; else blackout → menu
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
	dec player_lives
	beq reboot_to_menu
	lda #1					; restart same level (UI_DIRTY_ALL on init)
	sta level_want
.pdt_rts
	rts

; Blackout VIC and reboot to menu (game over / episode complete)
reboot_to_menu
	lda #$35
	sta $01
	lda #0
	sta $d020
	sta $d021
	sta $d015
	jmp REBOOT_STUB

; Walk-on exit tile 144
player_check_exit
	lda playerx_h
	sta tmp0
	lda playery_h
	sta tmp1
	jsr door_tile_at
	cmp #T_EXIT
	bne .pce_rts
	lda #2				; next level
	sta level_want
.pce_rts
	rts

; level_want: 1=restart 2=next 3=new game 4=secret — disk reload + re-init
; Player init after successful load so a failed LoadLevel can restore VIC.
handle_level_want
	lda level_want
	pha					; 1=restart 2=next 3=new 4=secret
	lsr
	bcs .hlw_gotwant			; odd: restart / new game
	; 2 or 4: 15,000 then jingle, hold until SID idle
	lda #150
	jsr score_add_hud_and_redraw
	lda #SOUND_LEVELDONE
	jsr play_sound
-	lda sound_index
	bpl -
.hlw_gotwant
	lda level_want
	cmp #2
	bne .hlw_chksecret
	lda level_num
	cmp #LEVEL_SECRET
	beq .hlw_from_secret
	cmp #LEVEL_MAX
	bne .hlw_adv
	; episode done — SP reset in reboot_game; skip pla / clear want
.hlw_epdone
	lda #1
	sta game_complete
	jmp reboot_to_menu
.hlw_from_secret
	ldx secret_from
	inx
	cpx #LEVEL_MAX + 1
	bcs .hlw_epdone
	stx level_num
	jsr player_reset_status
	jmp .hlw_load
.hlw_adv
	jsr advance_level			; needs new level_num before FormatDosName
	jmp .hlw_load
.hlw_chksecret
	cmp #4
	bne .hlw_chknew
	lda level_num
	sta secret_from
	lda #LEVEL_SECRET
	sta level_num
	jsr player_reset_status
	jmp .hlw_load
.hlw_chknew
	cmp #3
	bne .hlw_load
	lda #0
	sta secret_from
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
	cmp #1
	beq .hlw_life
	cmp #3
	bne .hlw_done				; 2 or 4: status already reset
	jsr player_init_game
	bne .hlw_wpn				; A = UI_DIRTY_ALL
.hlw_life
	jsr player_init_life
.hlw_wpn
	jsr init_weapon				; pistol sprites; I/O already $35
.hlw_done
	lda #0					; successful restart: restore black border
	sta $d020
	lda #$34
	sta $01
	cli
	rts

; Bump episode map index; clear keys/death; keep HP/ammo/weapons
advance_level
	ldx level_num
	inx
	cpx #LEVEL_MAX + 1
	bcc .al_set
	ldx #1
.al_set
	stx level_num
	jmp player_reset_status
