; Wolf64 — fat memory image (split into disk PRGs by tools/mkdisk.py)
; DDA: The Keep · multiply: Judd a²−b² · view: TechDesignDoc nibbles
!cpu 6502
!to "game_image.prg", cbm

; --- build flags (SquareDoom-style) ---------------------------------------
PROFILE		= 0				; stage buckets on bitmap row 0
PROF_SPLIT	= 0				; 1 = per-col R/D (~80 CIA samples; +~20ms)
DBG_FPS		= 0				; F ≈ frame ms (cols 0–2)
DBG_NO_DETECT	= 0				; 1 = enemies never spot player (patrol preview)
MAX_HALF_H	= 75				; painter clamp (1..50 unrolled, 51..75 looped)

; --- memory map -----------------------------------------------------------
; $0400  tables.asm (disk: tab)
; $0801  disposable boot → low BSS overlay (col_* / LoadPrg scrap)
; $08C0  reboot stub (installed at locode_entry); $08FD effects_vol; $08FE game_complete; $08FF difficulty
; $0900  locode — game code, no enemy modules (disk: locode); MENU overlay pre-load
;        col_wallz_h / col_enemy live after end_sfx (not on boot page)
; $033C  locode runtime BSS (cassette buffer; not in locode PRG)
; $3800  Judd SQTAB (disk: sqt; 2K in locode–screen gap)
; $4000  VIC screen A / B ($4400) (disk: scr)
; $4800  textures (disk: tex)
; $5000  weapon HUD sprites (disk: wpn; ends at ITEM_SPRITES)
; $5880  world item gfx (disk: itm; to bitmap $6000)
; $6000  bitmap (8K, disk: bmp)
; $8000  wall painters only (disk: paint)
; $B8F2  PC SFX (disk: sfx); item scratch + vis_depth/order/kind after end_sfx → <$C000
; $C000  enemy block — code, AI, gfx, hot SoA (disk: enemy); cold SoA @ $0100
; $0100  cold enemy tables under stack (vis_slot…enemy_type); STACK_GUARD=$01D0
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
	jsr install_reboot_stub
	lda #0
	sta episode
	sta load_in_play
	lda #2
	sta level_num
	jsr LoadLevel
	bcs .le_fail
	jmp game_start
.le_fail
	lda #$35				; keep $d020 = failed load color
	sta $01
.le_hang
	jmp .le_hang

; 3-byte trampoline at REBOOT_STUB → reboot_game (in enemy block; keeps locode under SQTAB)
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
	jsr init_vic
	jsr prof_init
	jsr input_irq_init
	jsr play_sound_init
	jsr player_init_game

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
	lda level_want
	beq .ml_alive
	jsr handle_level_want
	jmp .ml_render
.ml_alive
	lda player_dead
	beq .ml_play
	jsr player_death_tick
	jmp .ml_render
.ml_play
	jsr player_move
	jsr items_try_pickup
	jsr player_check_exit
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
	lda #$35
	sta $01
	lda wpn_visible			; deferred until first frame flipped
	bne .ml_wpn
	jsr show_weapon
.ml_wpn
	lda player_dead
	bne .ml_nower
	jsr update_weapon
.ml_nower
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
!source "painter_tables.asm"

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
!if end_locode > SQTAB1 {
	!error "Locode overlaps SQTAB1; end=$", end_locode
}
!warn "Locode free $", SQTAB1 - end_locode, " (end=$", end_locode, " limit SQTAB1=$", SQTAB1, ")"

; --- Locode runtime BSS in cassette buffer (not emitted into locode PRG) ---
; item_* scratch is in RAM after end_sfx; col_* overlays boot (bss.asm)
enemy_count	= TAPE_BSS
item_considered	= enemy_count + 1
los_rr		= item_considered + 1
walk_anim_t	= los_rr + 1			; global walk A/B ms accumulator
walk_phase	= walk_anim_t + 1		; 0=A, nonzero=B
player_hp	= walk_phase + 1
player_ammo	= player_hp + 1
player_keys	= player_ammo + 1
player_score_l	= player_keys + 1
player_score_h	= player_score_l + 1
player_lives	= player_score_h + 1
player_dead	= player_lives + 1
death_ms_l	= player_dead + 1
death_ms_h	= death_ms_l + 1
hurt_flash	= death_ms_h + 1		; 1=red this frame, 2=clear next
ui_dirty	= hurt_flash + 1
level_want	= ui_dirty + 1			; 0=none 1=restart 2=next
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
enemy_idx	= vis_tok + 1
probe_doors_pass = enemy_idx + 1
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
door_x		= e_pix + 16
door_y		= door_x + 8
door_pos	= door_y + 8
door_state	= door_pos + 8
door_orient	= door_state + 8
door_tic_l	= door_orient + 8
door_tic_h	= door_tic_l + 8
door_tile	= door_tic_h + 8
door_savex	= door_tile + 8
door_savetl	= door_savex + 1
door_saveth	= door_savetl + 1
turn_acc_l	= door_saveth + 1
turn_acc_h	= turn_acc_l + 1
frame_t0	= turn_acc_h + 1			; 4 bytes
frame_cy	= frame_t0 + 4
casc_now	= frame_cy + 4
end_tape_bss	= casc_now + 4
!if end_tape_bss > TAPE_BSS_END {
	!error "Tape BSS overflows cassette buffer; end=$", end_tape_bss
}

; =========================================================================
; scr — matrix A @ $4000, 24-byte sprite-ptr pad, matrix B @ $4400
; =========================================================================
*= SCREEN
!binary "../textures/ui/screen.bin", 2024
end_scr = *
!if end_scr != SCREEN_B + 1000 {
	!error "SCR must end at SCREEN_B+1000 ($47E8); end=$", end_scr
}
!if end_scr > TEXTURES {
	!error "Screen matrices overlap TEXTURES; end=$", end_scr
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
; itm — world props/pickups (4bpp + LUTs) @ $5880
; =========================================================================
*= ITEM_SPRITES
!source "items/item_gfx.asm"
item_gfx_data
!binary "../textures/items.bin"
!source "items_draw.asm"
end_itm = *
!if end_itm > BITMAP {
	!error "Item gfx overlap BITMAP; end=$", end_itm
}

; =========================================================================
; bmp — full MCM bitmap @ $6000 (UI + viewport pattern)
; =========================================================================
*= BITMAP
!binary "../textures/ui/bitmap.bin", 8000
; Profiler hexfont in unused VIC bitmap tail ($7F40..)
!source "_hexfont.inc"
end_bmp = *
!if end_bmp > PAINTERS {
	!error "Bitmap+hexfont overlap PAINTERS; end=$", end_bmp
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

; Column depth/hit buffers relocated off boot page (room for REBOOT_STUB)
col_wallz_h	= end_sfx
col_enemy	= col_wallz_h + 40
; Per-frame item scratch (map AABB cull) + vis depth/order — SFX→enemy gap
item_x		= col_enemy + 40
item_y		= item_x + MAX_VIS
item_frm	= item_y + MAX_VIS
vis_depth_l	= item_frm + MAX_VIS
vis_depth_h	= vis_depth_l + MAX_VIS
vis_order	= vis_depth_h + MAX_VIS		; sort tokens → vis_slot/vis_depth
vis_kind	= vis_order + MAX_VIS		; 0=enemy, 1=item (scratch idx in vis_slot)
end_item_soa	= vis_kind + MAX_VIS
!if end_item_soa > ENEMY_BASE {
	!error "Item/vis BSS overlaps ENEMY_BASE; end=$", end_item_soa
}

; Cold/runtime enemy tables under the stack ($0100..<$01D0) — not on enemy PRG
vis_slot	= STACK_BSS			; MAX_VIS entity ids (unsorted; kind in vis_kind)
enemy_burst	= vis_slot + MAX_VIS
enemy_state_t	= enemy_burst + 32
enemy_type	= enemy_state_t + 32		; cold: spawn / AI branch
end_stack_bss	= enemy_type + 32
!if end_stack_bss > STACK_GUARD {
	!error "Stack BSS hits STACK_GUARD; end=$", end_stack_bss
}

; =========================================================================
; enemy — @ $C000 (code, gfx, AI/helpers, painters, pixels, hot SoA)
; =========================================================================
*= ENEMY_BASE
!source "enemy.asm"
!source "enemy_gfx.asm"
!source "enemy_ai.asm"
!source "enemy_painters.asm"
enemy_gfx_data
!binary "../textures/enemies.bin"
; Enemy SoA (hot fields; cold tables under stack — STACK_BSS / enemy_type)
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
enemy_perp_l
!fill 32, 0
enemy_perp_h
!fill 32, 0
enemy_hp
!fill 32, 0
enemy_state
!fill 32, 0
end_enemy = *
!if end_enemy > MAP {
	!error "Enemy block overlaps MAP; end=$", end_enemy
}
!warn "Enemy free $", MAP - end_enemy, " (end=$", end_enemy, " limit MAP=$", MAP, ")"
