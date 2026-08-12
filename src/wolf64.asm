; Wolf64 — fat memory image (split into disk PRGs by tools/mkdisk.py)
; DDA: The Keep · multiply: Judd a²−b² · view: TechDesignDoc nibbles
!cpu 6502
!to "game_image.prg", cbm

; --- build flags (SquareDoom-style) ---------------------------------------
PROFILE		= 1				; stage buckets on bitmap row 0
PROF_SPLIT	= 0				; 1 = per-col R/D (~80 CIA samples; +~20ms)
DBG_FPS		= 1				; F ≈ frame ms (cols 0–2)
DBG_NO_DETECT	= 1				; 1 = enemies never spot player (patrol preview)
MAX_HALF_H	= 75				; painter clamp (1..50 unrolled, 51..75 looped)

; --- memory map -----------------------------------------------------------
; $0400  tables.asm (disk: tab)
; $0801  disposable boot → low BSS overlay (col_* / LoadPrg scrap)
; $0900  locode — game code, no enemy modules (disk: locode)
; $3800  Judd SQTAB (disk: sqt; 2K in locode–screen gap)
; $4000  VIC screen A / B ($4400)
; $4800  textures (disk: tex)
; $5000  weapon HUD sprites (disk: wpn; ends at ITEM_SPRITES)
; $5880  item HUD sprites (reserved; to bitmap $6000)
; $6000  bitmap (8K, runtime fill)
; $8000  wall painters only (disk: paint)
; $B8F2  PC SFX (disk: sfx)
; $C000  enemy block — code, AI, hi, pixels, SoA (disk: enemy)
; $EF00  map (disk: e1m1… via LoadLevel)

!source "mem.asm"
!source "zp.asm"
!source "bss.asm"

; =========================================================================
; tab — render tables @ $0400 (fat image starts here)
; =========================================================================
*= TABLES
!source "tables.asm"
end_tab = *
!if end_tab > LOADER_BASE {
	!error "Tables overlap boot/BSS; end=$", end_tab
}

; =========================================================================
; locode — resident low code (no enemy modules)
; =========================================================================
*= LOCODE_BASE

; Boot jumps here after LOADing locode + assets (map still on disk)
locode_entry
	lda #0
	sta episode
	lda #1
	sta level_num
	jsr LoadLevel
	bcs .le_fail
	jmp game_start
.le_fail
	lda #$35				; keep $d020 = failed load color
	sta $01
.le_hang
	jmp .le_hang

game_start
	sei
	lda #$35
	sta $01					; I/O in for VIC/SID/CIA init

	lda #$ff
	sta $dc02
	lda #0
	sta $dc03

	; KERNAL LOAD clobbered ZP — Judd table hi ptrs (tables LOADed by boot)
	jsr init_sqtabs
	jsr init_vic
	jsr prof_init
	jsr input_irq_init
	jsr play_sound_init

	lda #$ff
	sta smc_last_page
	sta smc_last_h

	jsr init_weapon			; needs VIC sprites ($d0xx) while I/O in
	lda #$34
	sta $01					; I/O out — enemy block spans $D000–$DFFF
	jsr doors_clear
	jsr find_spawn
	jsr enemies_init
	cli
	jmp main_loop

main_loop
	jsr calc_frame_dt
	jsr player_move
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
	jsr render_frame
	lda #$35
	sta $01
	jsr update_weapon
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
!source "render.asm"
!source "player.asm"
!source "weapon.asm"
!source "painter_tables.asm"

; --- BSS after code (col_* overlays boot; see bss.asm) --------------------
enemy_count
!byte 0
los_rr
!byte 0
player_hp
!byte 0
ai_dx
!byte 0
ai_dy
!byte 0
ai_steps
!byte 0
ai_xl
!byte 0
ai_xh
!byte 0
ai_yl
!byte 0
ai_yh
!byte 0
ai_xsl
!byte 0
ai_xsh
!byte 0
ai_ysl
!byte 0
ai_ysh
!byte 0
ai_dist
!byte 0
ai_turn
!byte 0
ai_old
!byte 0
ai_dirtry
!fill 5, 0
vis_count
!byte 0
vis_i
!byte 0
enemy_idx
!byte 0
probe_doors_pass
!byte 0
e_dx_l
!byte 0
e_dx_h
!byte 0
e_dy_l
!byte 0
e_dy_h
!byte 0
e_mul
!byte 0
e_acc_l
!byte 0
e_acc_h
!byte 0
e_side_l
!byte 0
e_side_h
!byte 0
e_spr_h
!byte 0
e_top
!byte 0
e_bot
!byte 0
e_view
!byte 0
e_frm_base
!byte 0
e_src_i
!byte 0
e_flip
!byte 0
e_frm
!byte 0
e_frm_w
!byte 0
e_frm_h
!byte 0
e_scr_w
!byte 0
e_col_cx
!byte 0
e_col0
!byte 0
e_sx
!byte 0
e_scol
!byte 0
e_scol_raw
!byte 0
e_scol_cache
!byte 0
e_u_numer
!byte 0
e_u_denom
!byte 0
e_clip_skip
!byte 0
e_gfx_l
!byte 0
e_gfx_h
!byte 0
e_step_l
!byte 0
e_step_h
!byte 0
e_row
!byte 0
e_pix
!fill 16, 0
door_x
!fill 8, 0
door_y
!fill 8, 0
door_pos
!fill 8, 0
door_state
!fill 8, 0
door_orient
!fill 8, 0
door_tic_l
!fill 8, 0
door_tic_h
!fill 8, 0
door_tile
!fill 8, 0
door_savex
!byte 0
door_savetl
!byte 0
door_saveth
!byte 0
turn_acc_l
!byte 0
turn_acc_h
!byte 0
frame_t0
!fill 4, 0
frame_cy
!fill 4, 0
casc_now
!fill 4, 0
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
!if end_locode > SQTAB1 {
	!error "Locode overlaps SQTAB1; end=$", end_locode
}

; =========================================================================
; tex — walls @ $4800
; =========================================================================
*= TEXTURES
!binary "../textures/walls.bin", 2048
end_tex = *

; =========================================================================
; wpn — knife/pistol/MG/chaingun HUD sprites
; =========================================================================
*= WPN_SPRITES
!source "weapons/wpn_data.asm"
end_wpn = *
!if end_wpn > ITEM_SPRITES {
	!error "Weapon sprites overlap ITEM_SPRITES; end=$", end_wpn
}

; =========================================================================
; paint — wall height painters only
; =========================================================================
*= PAINTERS
!binary "painters.bin", PAINTERS_SIZE
end_paint = *
!if end_paint != SFX_BASE {
	!error "painters.bin size drift; end=$", end_paint, " expected SFX_BASE=$", SFX_BASE
}

; =========================================================================
; sfx — PC sounds @ $B8F2 (after painters)
; =========================================================================
*= SFX_BASE
!source "pcsounds.asm"
!source "pcsfreq.asm"
end_sfx = *
!if end_sfx > ENEMY_BASE {
	!error "SFX overlaps ENEMY_BASE; end=$", end_sfx
}

; =========================================================================
; enemy — contiguous block @ $C000 (code, gfx, AI/helpers, painters, pixels, SoA)
; =========================================================================
*= ENEMY_BASE
!source "enemy.asm"
!source "enemy_gfx.asm"
!source "enemy_ai.asm"
!source "enemy_painters.asm"
enemy_gfx_data
!binary "../textures/enemies.bin"
; Enemy SoA + vis order
enemy_xh
!fill 32, 0
enemy_xl
!fill 32, 0
enemy_yh
!fill 32, 0
enemy_yl
!fill 32, 0
enemy_facing
!fill 32, 0
enemy_flags
!fill 32, 0
enemy_anim_t
!fill 32, 0
enemy_view
!fill 32, 0
enemy_depth_l
!fill 32, 0
enemy_depth_h
!fill 32, 0
enemy_perp_l
!fill 32, 0
enemy_perp_h
!fill 32, 0
enemy_hp
!fill 32, 0
enemy_state
!fill 32, 0
enemy_state_t
!fill 32, 0
enemy_type
!fill 32, 0
enemy_burst
!fill 32, 0
vis_slot
!fill 32, 0
end_enemy = *
!if end_enemy > MAP {
	!error "Enemy block overlaps MAP; end=$", end_enemy
}
!if (end_enemy - ENEMY_BASE) != ENEMY_SIZE {
	!error "ENEMY_SIZE mismatch; update mem.asm (got $", end_enemy - ENEMY_BASE, ")"
}
