; Wolf64 — fat memory image (split into disk PRGs by tools/mkdisk.py)
; DDA: The Keep · multiply: Judd a²−b² · view: TechDesignDoc nibbles
; !cpu 6502: exclude undocumented opcodes for SuperCPU compatibility
!cpu 6502
!to "../generated/game_image.prg", cbm

; --- build flags (SquareDoom-style) ---------------------------------------
PROFILE		= 0				; locode too tight with buckets; F via DBG_FPS
PROF_SPLIT	= 0				; 1 = per-col R/D (~80 CIA samples; +~20ms)
DBG_FPS		= 0				; F ≈ frame ms (cols 0–2)
DBG_NO_DETECT	= 0				; 1 = enemies never spot player (patrol preview)
MAX_HALF_H	= 75				; painter clamp (1..50 unrolled, 51..75 looped)
NEAR_LO		= 51				; first looped (Bresenham) height; below this, TEX_HI/TEX_LO, no SMC

; --- memory map -----------------------------------------------------------
; USE_KRILL=1: Krill loadraw at $4E00. Default: KERNAL LOAD.
; $0400  tables.asm (disk: tab)
; $0801  disposable boot → low BSS overlay (col_* / LoadPrg scrap)
; $08C0  reboot stub; $08FD effects_vol; $08FE game_complete; $08FF difficulty
; $0900  ALL game code (locode+enemy*.asm+items_draw); MENU overlay pre-load
; $033C  tape BSS (temps; not in locode PRG)
; $4E00  Krill hole (both disks)
; $4805…$4E00 SFX in locode→Krill gap (exact start = end_locode)
; $5000  paint → enemy pixels (≤$8000); scratch BSS after egfx
; $8000  VIC bank (%01): scr A/B, BJH, WPN_STAGE; WPN_MASTER+itm in $9000 hole
; $9BAD  GAME_STATE (863 B, QS file); scratch @ $D800
; $A000  MCM bitmap 8K (disk: bmp); score in UI hole
; $C000  MAP 4K (disk: e1m*; also SQT load staging → copy to $D000)
; $D000  Judd SQTAB 2K (RAM after install_sqtabs); $D800 item/vis scratch
; $E000  TEX_LO (disk: texlo); $F000 TEX_HI (RAM-built)
; $0100  vis_slot + vis_perp; STACK_GUARD=$01D0

!source "mem.asm"
!source "zp.asm"
!source "../generated/src/bss.asm"

; =========================================================================
; tab — render tables @ $0400 (fat image starts here)
; =========================================================================
*= TABLES
!source "../generated/src/tables.asm"
end_tab = *
!if end_tab > LOADER_BASE {
	!error "Tables overlap boot/BSS; end=$", end_tab
}

; =========================================================================
; locode — all game code (≤ KRILL_HOLE)
; =========================================================================
*= LOCODE_BASE

; Boot jumps here after LOADing locode + assets (SQT staged at MAP; map still on disk)
locode_entry
	jsr install_reboot_stub
	lda #0
	sta episode
	sta load_in_play
	sta secret_from
	lda #1
	sta level_num
	jsr install_sqtabs			; $C000 → $D000 before LoadLevel
	jsr LoadLevel
	bcs .le_fail
	jmp game_start
.le_fail
	lda #$35
	sta $01
	jsr init_vic
	lda #$02				; red border = map load failed
	sta $d020
.le_hang
	jmp .le_hang

; 3-byte trampoline at REBOOT_STUB → reboot_game
install_reboot_stub
	lda #$4c
	sta REBOOT_STUB
	lda #<reboot_game
	sta REBOOT_STUB+1
	lda #>reboot_game
	sta REBOOT_STUB+2
	rts

game_start
	sei
	lda #$35
	sta $01					; I/O in for VIC/SID/CIA init
	jsr init_vic				; bitmap mode, DEN off until first swap_view

	lda #$ff
	sta $dc02
	lda #0
	sta $dc03

	; Tape BSS is absolute RAM (not in locode PRG) — clear once
	ldx #0
	txa
.gs_cltape
	sta TAPE_BSS,x
	inx
	cpx #(end_tape_bss - TAPE_BSS)
	bne .gs_cltape

	; KERNAL LOAD clobbered ZP — Judd table hi ptrs (tables LOADed by boot)
	jsr init_sqtabs
	jsr init_tex_hi				; TEX_LO is disk-loaded; TEX_HI is derived once, in RAM
	jsr prof_init
	jsr input_irq_init
	jsr play_sound_init
	jsr player_init_game

	jsr init_weapon			; snapshot for raster-88 blit (no VIC)
	lda #$34
	sta $01					; I/O out — TEX_HI / SQTAB / scratch under I/O hole
	jsr doors_clear
	jsr find_spawn
	jsr enemies_init
	cli
	jmp main_loop

main_loop
	jsr calc_frame_dt
	lda level_want
	beq .ml_alive
	jsr handle_level_want
	jmp .ml_render
.ml_alive
	jsr poll_quick_keys			; F5/F7 / F3+W warp; works while dead too
	bcs .ml_render				; disk op done — repaint
	lda player_dead
	beq .ml_play
	jsr player_death_tick
	jmp .ml_render
.ml_play
	jsr player_move
	jsr items_try_pickup
	jsr player_check_exit
	lda level_want
	bne .ml_render			; freeze: no AI/doors on the exit frame
!if PROFILE = 1 {
	jsr prof_reset_frame
}
	jsr enemies_update
!if PROFILE = 1 {
	ldy #PROF_OBJUPD
	jsr prof_add_bucket
}
	jsr doors_update
!if PROFILE = 1 {
	jsr prof_snap
}
.ml_render
	jsr render_frame
	lda wpn_visible			; deferred until first frame flipped
	bne .ml_wpn
	jsr show_weapon
.ml_wpn
	lda player_dead
	bne .ml_ui
	jsr update_weapon		; col_enemy visible at $34
.ml_ui
	lda #$35
	sta $01
	jsr ui_update
	jsr player_border_tick		; needs I/O ($d020)
	lda #$34
	sta $01
	jsr prof_frame_sample
	jsr prof_print
	jmp main_loop

!source "mul.asm"
!source "vic.asm"
!source "profil.asm"
!source "input.asm"
!source "playsound.asm"
!source "loader.asm"
!source "dda.asm"
!source "doors.asm"
!source "pushwall.asm"
!source "render.asm"
!source "player.asm"
!source "weapon.asm"
!source "items.asm"
!source "items_draw.asm"
!source "enemy.asm"
!source "../generated/src/enemy_gfx.asm"
!source "enemy_ai.asm"
!source "../generated/src/enemy_painters.asm"

; PROFILE-only BSS stays in locode PRG (won't fit leftover tape slack)
!if PROFILE = 1 {
casc_snap
!fill 4, 0
prof_dt
!fill 4, 0
los_t0
!fill 4, 0
prof_cy
!fill 6 * 4, 0
}

end_locode = *
!if end_locode > KRILL_HOLE {
	!error "Locode overlaps Krill hole; end=$", end_locode
}
!warn "Locode free $", KRILL_HOLE - end_locode, " (end=$", end_locode, " limit KRILL_HOLE=$", KRILL_HOLE, ")"

SFX_BASE = end_locode

; --- Tape BSS (temps only; saveable state lives in GAME_STATE) ------------
item_considered	= TAPE_BSS
los_rr		= item_considered + 1
walk_anim_t	= los_rr + 1			; global walk A/B ms accumulator
walk_phase	= walk_anim_t + 1		; 0=A, nonzero=B
level_want	= walk_phase + 1		; 0=none 1=restart 2=next 3=new 4=secret 5=warp
ai_dx		= level_want + 1
ai_dy		= ai_dx + 1
ai_steps	= ai_dy + 1
ai_xl		= ai_steps + 1
ai_xh		= ai_xl + 1
ai_yl		= ai_xh + 1
ai_yh		= ai_yl + 1
ai_xsl		= ai_yh + 1
ai_xsh		= ai_xsl + 1
ai_ysl		= ai_xsh + 1
ai_ysh		= ai_ysl + 1
ai_dist		= ai_ysh + 1
ai_turn		= ai_dist + 1
ai_old		= ai_turn + 1
ai_dirtry	= ai_old + 1			; 5 bytes
vis_count	= ai_dirtry + 5
vis_i		= vis_count + 1
vis_tok		= vis_i + 1			; stable vis_slot/vis_depth index
probe_doors_pass = vis_tok + 1
e_dx_l		= probe_doors_pass + 1
e_dx_h		= e_dx_l + 1
e_dy_l		= e_dx_h + 1
e_dy_h		= e_dy_l + 1
e_mul		= e_dy_h + 1
e_acc_l		= e_mul + 1
e_acc_h		= e_acc_l + 1
e_side_l	= e_acc_h + 1
e_side_h	= e_side_l + 1
e_spr_h		= e_side_h + 1
e_top		= e_spr_h + 1
e_bot		= e_top + 1
e_view		= e_bot + 1
e_frm_base	= e_view + 1
e_src_i		= e_frm_base + 1
e_flip		= e_src_i + 1
e_frm		= e_flip + 1
e_frm_w		= e_frm + 1
e_frm_h		= e_frm_w + 1
e_scr_w		= e_frm_h + 1
e_col_cx	= e_scr_w + 1
e_col0		= e_col_cx + 1
e_sx		= e_col0 + 1
e_scol		= e_sx + 1
e_scol_raw	= e_scol + 1
e_scol_cache	= e_scol_raw + 1
e_u_numer	= e_scol_cache + 1
e_u_denom	= e_u_numer + 1
e_clip_skip	= e_u_denom + 1
e_gfx_l		= e_clip_skip + 1
e_gfx_h		= e_gfx_l + 1
e_step_l	= e_gfx_h + 1
e_step_h	= e_step_l + 1
e_row		= e_step_h + 1
e_pix		= e_row + 1			; 16 bytes
door_savex	= e_pix + 16
door_savetl	= door_savex + 1
door_saveth	= door_savetl + 1
turn_acc_l	= door_saveth + 1
turn_acc_h	= turn_acc_l + 1
mouse_x		= turn_acc_h + 1			; last SID POTX ($d419)
frame_t0	= mouse_x + 1			; 4 bytes
frame_cy	= frame_t0 + 4
casc_now	= frame_cy + 4
face_tic_l	= casc_now + 4			; Wolf look cadence (dt_ms countdown)
face_tic_h	= face_tic_l + 1
bjh_look	= face_tic_h + 1		; 0=left 1=center 2=right
warp_armed	= bjh_look + 1			; F3+W chord waiting for 1–8/B/S
warp_w_prev	= warp_armed + 1
warp_dig_prev	= warp_w_prev + 1
end_tape_bss	= warp_dig_prev + 1
!if end_tape_bss > TAPE_BSS_END {
	!error "Tape BSS overflows cassette buffer; end=$", end_tape_bss
}

; --- GAME_STATE symbols (address = end_itm; set after itm binary) --------
; Layout matches QS file body: hdr(7) + player(23) + doors(64) + count + SoA
; GAME_STATE itself is assigned after end_itm below.
gs_player	= GAME_STATE + QS_OFF_PLAYER
; +0..4 / +9..10 / +22 = ZP / difficulty mirrors (patched around SAVE/LOAD)
player_hp	= gs_player + 5
player_lives	= gs_player + 6
player_ammo	= gs_player + 7
player_keys	= gs_player + 8
player_score_l	= gs_player + 11
player_score_h	= gs_player + 12
score_1up_l	= gs_player + 13
score_1up_h	= gs_player + 14
player_dead	= gs_player + 15
death_ms_l	= gs_player + 16
death_ms_h	= gs_player + 17
hurt_flash	= gs_player + 18
; +19..21 episode/level_num/secret_from — live in low BSS (KERNAL LOAD);
; qs_patch_in/out copies them. +22 difficulty ($08FF).

door_x		= GAME_STATE + QS_OFF_DOORS
door_y		= door_x + 8
door_pos	= door_y + 8
door_state	= door_pos + 8
door_orient	= door_state + 8
door_tic_l	= door_orient + 8
door_tic_h	= door_tic_l + 8
door_tile	= door_tic_h + 8

enemy_count	= GAME_STATE + QS_OFF_ECOUNT
enemy_xh		= GAME_STATE + QS_OFF_ENEMY
enemy_xl		= enemy_xh + MAX_ENEMIES
enemy_yh		= enemy_xl + MAX_ENEMIES
enemy_yl		= enemy_yh + MAX_ENEMIES
enemy_facing	= enemy_yl + MAX_ENEMIES
enemy_flags	= enemy_facing + MAX_ENEMIES
enemy_state_t	= enemy_flags + MAX_ENEMIES
enemy_type	= enemy_state_t + MAX_ENEMIES
enemy_hp		= enemy_type + MAX_ENEMIES
enemy_state	= enemy_hp + MAX_ENEMIES
enemy_vel_rem	= enemy_state + MAX_ENEMIES
enemy_burst	= enemy_vel_rem + MAX_ENEMIES

; Per-frame scratch in I/O window ($01=$34 only)
col_wallz_h	= ITM_SCRATCH
item_x		= col_wallz_h + 40
item_y		= item_x + MAX_VIS
item_frm	= item_y + MAX_VIS
vis_depth_l	= item_frm + MAX_VIS
vis_depth_h	= vis_depth_l + MAX_VIS
vis_order	= vis_depth_h + MAX_VIS
vis_kind	= vis_order + MAX_VIS
col_enemy	= vis_kind + MAX_VIS
end_itm_bss	= col_enemy + 40
!if end_itm_bss > TEX_HI_R15 {
	!error "Item scratch overlaps TEX_HI_R15; end=$", end_itm_bss
}
!if TEX_HI_R15 + 256 > TEX_LO {
	!error "TEX_HI_R15 overlaps TEX_LO"
}

; Under stack: vis list + perp
vis_slot	= STACK_BSS			; MAX_VIS entity ids (unsorted; kind in vis_kind)
vis_perp_l	= vis_slot + MAX_VIS
vis_perp_h	= vis_perp_l + MAX_VIS
end_stack_bss	= vis_perp_h + MAX_VIS
!if end_stack_bss > STACK_GUARD {
	!error "Stack BSS hits STACK_GUARD; end=$", end_stack_bss
}

; =========================================================================
; sfx — PC sounds in locode→Krill gap
; =========================================================================
*= SFX_BASE
!source "../generated/src/pcsounds.asm"
!source "../generated/src/pcsfreq.asm"

; Open only the neighbor we are walking into: wish on that axis, and either
; already on that keep-out face or this step's dest hi is that neighbor.
player_bump_then_push
	lda move_dx_h
	bmi .pbt_west
	ora move_dx_l
	beq .pbt_y
	lda playerx_l
	cmp #$100 - WALL_MARGIN
	bcs .pbt_east
	clc
	adc move_dx_l
	lda playerx_h
	adc move_dx_h
	cmp playerx_h
	beq .pbt_y
.pbt_east
	lda playerx_h
	clc
	adc #1
	sta mapx
	lda playery_h
	sta mapy
	jsr try_open_door
	jmp .pbt_y
.pbt_west
	lda playerx_l
	cmp #WALL_MARGIN + 1
	bcc .pbt_westgo
	clc
	adc move_dx_l
	lda playerx_h
	adc move_dx_h
	cmp playerx_h
	beq .pbt_y
.pbt_westgo
	lda playerx_h
	sec
	sbc #1
	sta mapx
	lda playery_h
	sta mapy
	jsr try_open_door
.pbt_y
	lda move_dy_h
	bmi .pbt_north
	ora move_dy_l
	beq .pbt_push
	lda playery_l
	cmp #$100 - WALL_MARGIN
	bcs .pbt_south
	clc
	adc move_dy_l
	lda playery_h
	adc move_dy_h
	cmp playery_h
	beq .pbt_push
.pbt_south
	lda playerx_h
	sta mapx
	lda playery_h
	clc
	adc #1
	sta mapy
	jsr try_open_door
	jmp .pbt_push
.pbt_north
	lda playery_l
	cmp #WALL_MARGIN + 1
	bcc .pbt_northgo
	clc
	adc move_dy_l
	lda playery_h
	adc move_dy_h
	cmp playery_h
	beq .pbt_push
.pbt_northgo
	lda playerx_h
	sta mapx
	lda playery_h
	sec
	sbc #1
	sta mapy
	jsr try_open_door
.pbt_push
	lda #WALL_MARGIN
	jmp push_walls

end_sfx = *
!if end_sfx > KRILL_HOLE {
	!error "SFX overlaps Krill hole; end=$", end_sfx
}
!warn "SFX/Krill free $", KRILL_HOLE - end_sfx, " (end_sfx=$", end_sfx, ")"

; =========================================================================
; paint — wall height painters @ $5000 (after Krill)
; =========================================================================
*= PAINT_BASE
PAINTERS = PAINT_BASE
!source "../generated/src/painters.asm"
end_paint = *
ENEMY_GFX_BASE = end_paint

; =========================================================================
; egfx — enemy pixel blob (follows paint; ≤ SCREEN)
; warp.asm sits in the leftover bytes before SCREEN ($8000).
; =========================================================================
*= ENEMY_GFX_BASE
enemy_gfx_data
!binary "../generated/textures/enemies.bin"
!source "warp.asm"
end_egfx = *
!if end_egfx > SCREEN {
	!error "Enemy gfx overlaps SCREEN; end=$", end_egfx
}
!warn "Paint/egfx free $", SCREEN - end_egfx, " (end_egfx=$", end_egfx, ")"

; =========================================================================
; scr — matrix A @ $8000, pad, matrix B @ $8400
; =========================================================================
*= SCREEN
!binary "../generated/textures/ui/screen.bin", 2024
end_scr = *
!if end_scr != SCREEN_B + 1000 {
	!error "SCR must end at SCREEN_B+1000; end=$", end_scr
}
!if end_scr > BJH_SPRITES {
	!error "Screen matrices overlap BJH_SPRITES; end=$", end_scr
}

; =========================================================================
; bjh — 10 BJ-head HUD sprites @ $8800
; =========================================================================
*= BJH_SPRITES
!source "../generated/src/bjhead_spr.asm"
end_bjh = *
; VIC-visible stage for active weapon (≤8 sprites); 64-byte aligned
WPN_STAGE = ((end_bjh + 63) / 64) * 64
WPN_STAGE_PTR0 = (WPN_STAGE - SCREEN) / 64
!if WPN_STAGE + WPN_STAGE_SLOTS * 64 > WPN_MASTER {
	!error "WPN_STAGE overlaps char-ROM hole; stage=$", WPN_STAGE
}

; =========================================================================
; wpn — full HUD sprite master in hole @ $9000 (staged into WPN_STAGE)
; =========================================================================
*= WPN_MASTER
!source "../generated/src/weapons/wpn_data.asm"
end_wpn = *
ITEM_SPRITES = end_wpn

; =========================================================================
; itm — world props/pickups (CPU; may sit in VIC hole); draw code in locode
; =========================================================================
*= ITEM_SPRITES
!source "../generated/src/items/item_gfx.asm"
item_gfx_data
!binary "../generated/textures/items.bin"
end_itm = *
!if end_itm > BITMAP {
	!error "Item gfx overlaps BITMAP; end=$", end_itm
}

; Quicksave state in pre-bitmap pocket (KERNAL SAVE-safe)
GAME_STATE = end_itm
QS_GS_END = GAME_STATE + QS_STATE_SIZE
!if QS_GS_END > BITMAP {
	!error "GAME_STATE overlaps BITMAP; end=$", QS_GS_END
}

; =========================================================================
; bmp — full MCM bitmap @ $A000
; Hidden code: row 3 cols 30–39, skip digit bottoms, rest of row 4.
; =========================================================================
*= BITMAP
!binary "../generated/textures/ui/bitmap.bin", 3 * 320 + 30 * 8
!source "score.asm"
end_score = *
!if end_score > BITMAP + 5 * 320 {
	!error "Score code overlaps 3D bitmap row 5; end=$", end_score
}
!warn "Score code free $", BITMAP + 5 * 320 - end_score, " (end=$", end_score, ")"
*= BITMAP + 4 * 320
!binary "../generated/textures/ui/bitmap.bin", 10 * 8, 4 * 320
*= BITMAP + 5 * 320
!binary "../generated/textures/ui/bitmap.bin", 20 * 320, 5 * 320
!source "_hexfont.inc"
end_bmp = *
!if end_bmp > MAP {
	!error "Bitmap+hexfont overlap MAP; end=$", end_bmp
}

; =========================================================================
; tex_lo — TEX_LO @ $E000; TEX_HI @ $F000 filled by init_tex_hi
; =========================================================================
*= TEX_LO
!binary "../generated/textures/tex_lo.bin", 4096
end_tex_lo = *
!if end_tex_lo != TEX_HI {
	!error "tex_lo.bin size drift; end=$", end_tex_lo, " expected TEX_HI=$", TEX_HI
}
