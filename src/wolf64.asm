; Wolf64 — C64 textured ray walker (map 0)
; DDA: The Keep · multiply: Judd a²−b² · view: TechDesignDoc nibbles
!cpu 6502
!to "wolf64.prg", cbm

; --- build flags (SquareDoom-style) ---------------------------------------
PROFILE		= 1				; stage buckets on bitmap row 0
PROF_SPLIT	= 0				; 1 = per-col R/D (~80 CIA samples; +~20ms)
DBG_FPS		= 1				; F ≈ frame ms (cols 0–2)
MAX_HALF_H	= 75				; painter clamp (1..50 unrolled, 51..75 looped)

; --- memory map -----------------------------------------------------------
; $0801  BASIC stub + code + small BSS
; $4000  VIC screen A (bank 1)
; $4400  VIC screen B (double-buffer)
; $4800  textures (2K)
; $5000  weapon sprites (pistol / chaingun / muzzle)
; $6000  bitmap (8K, shared)
; $8000  compiled height painters
; ~$B900  enemy SoA + packed guard frames
; $C000  map (4K) — PRG must not extend into $D000 I/O
; $E000  Judd SQTAB (2K, filled at runtime; KERNAL out)

SCREEN		= $4000
SCREEN_B	= $4400
BITMAP		= $6000
TEXTURES	= $4800
PISTOL_SPRITES		= $5000			; 6×64
MINIGUN_B_SPRITES	= $5180			; 3×64 chaingun frame B
MINIGUN_SPRITES		= $5240			; 6×64 chaingun A/shared
MUZZLE_FLASH_SPRITES	= $53C0			; 4×64 shared flash A/B
PAINTERS	= $8000
MAP		= $C000
SQTAB1		= $E000			; runtime only — never *= into the PRG
SQTAB2		= SQTAB1 + $200
SQTAB3		= SQTAB1 + $400
SQTAB4		= SQTAB1 + $600

; Spawn: map tiles 48..51 = player N,E,S,W (see find_spawn)

!source "zp.asm"

*= $0801
!byte $0b,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00

*= $080d
start
	sei
	lda #$35
	sta $01					; stay here: VIC/CIA. $34 only inside render_frame

	lda #$ff
	sta $dc02
	lda #0
	sta $dc03

	jsr init_sqtabs
	jsr init_vic
	jsr prof_init
	jsr input_irq_init

	lda #$ff
	sta smc_last_page
	sta smc_last_h

	jsr find_spawn
	jsr enemies_init
	jsr init_weapon
	cli					; CIA1 Timer A key sampling

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
	jsr prof_snap			; doors not folded into C/R
}
	jsr render_frame
	jsr update_weapon
	jsr prof_frame_sample
	jsr prof_print
	jmp main_loop

!source "mul.asm"
!source "vic.asm"
!source "profil.asm"
!source "input.asm"
!source "dda.asm"
!source "doors.asm"
!source "render.asm"
!source "player.asm"
!source "weapon.asm"
!source "enemy.asm"
!source "enemy_gfx.asm"
!source "enemy_painters.asm"
!source "painter_tables.asm"

col_texid
!fill 40, 0
col_half_h
!fill 40, 0
col_texx
!fill 40, 0
col_wallz_l
!fill 40, 0
col_wallz_h
!fill 40, 0
col_enemy
!fill 40, $ff				; enemy index per column; $ff = empty

; --- enemy SoA (MAX_ENEMIES = 32) arrays live after painters (see below) ---
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
!byte 0					; 1 = unlocked doors non-solid (enemy patrol)
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

; Door anim slots (NUM_DOOR_SLOTS = 8)
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

; Profiler BSS (SquareDoom PROF_BSS layout, trimmed)
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
prof_cy						; NBUCKET × 4-byte cycle totals
!fill PROF_NBUCKET * 4, 0
}

end_code = *
!if end_code > SCREEN {
	!error "Code overlaps SCREEN at $4000; end=$", end_code
}

*= TEXTURES
!binary "../textures/walls.bin", 2048

; Weapon HUD sprites (VIC bank 1) — after textures, before bitmap
*= PISTOL_SPRITES
!source "weapons/pistol_sprites.asm"
*= MINIGUN_B_SPRITES
!source "weapons/minigun_weapon.asm"
*= MUZZLE_FLASH_SPRITES
!source "weapons/muzzle_flash.asm"
end_wpn_spr = *
!if end_wpn_spr > BITMAP {
	!error "Weapon sprites overlap BITMAP at $6000; end=$", end_wpn_spr
}

; Tables + enemy AI in VIC bank gap before bitmap ($54C0..$5FFF)
*= end_wpn_spr
!source "tables.asm"
!source "enemy_ai.asm"
end_ai_tables = *
!if end_ai_tables > BITMAP {
	!error "AI/tables overlap BITMAP at $6000; end=$", end_ai_tables
}

*= PAINTERS
!binary "painters.bin"

; Enemy SoA + vis order + frame pixels — before map at $C000
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
vis_slot
!fill 32, 0

ENEMY_GFX = *
enemy_gfx_data
!binary "../textures/enemies.bin"
end_enemy_gfx = *
!if end_enemy_gfx > MAP {
	!error "Enemy gfx overlaps MAP at $C000; end=$", end_enemy_gfx
}

*= MAP
!binary "../maps/00_Wolf1_Map1.bin", 4096
end_map = *
!if end_map > $d000 {
	!error "Map extends into I/O at $D000; end=$", end_map
}
