; First-person HUD: knife / pistol / machinegun / chaingun
; All sprites XY-expanded (2×). Flash: white + 1/2/3 red (pistol/MG/chaingun).
; Chaingun flash A/B = distinct blobs; mg_frame selects ptr + XY slots.
!source "../generated/src/weapons/wpn_tables.asm"
!zone weapon

WPN_KNIFE = 0
WPN_PISTOL = 1
WPN_MG = 2
WPN_CHAINGUN = 3

POSE_IDLE = 0
POSE_FIRE = 1
POSE_RECOIL = 2

MUZZLE_MS = 300
RECOIL_MS = 150

wpn_own_bit
	!byte $01, $02, $04, $08

wpn_fire_ms_lo
	!byte <400, <600, <100, <100
wpn_fire_ms_hi
	!byte >400, >600, >100, >100

wpn_sound
	!byte SOUND_ATKKNIFE, SOUND_ATKPISTOL, SOUND_ATKMACHINEGUN, SOUND_ATKGATLING

; weapon*3 + pose
wpn_pose_dx
	!byte 15, 0, 0
	!byte 0, 0, 0
	!byte 0, 0, 0
	!byte 0, 0, 0
wpn_pose_dy
	!byte 15, 0, 0
	!byte 6, 2, 0
	!byte 6, 2, 0
	!byte 6, 2, 0

; X = weapon id. Gated by owned_weapons.
switch_weapon
	lda wpn_own_bit,x
	bit owned_weapons
	beq .sw_done
	cpx cur_weapon
	beq .sw_done
	stx cur_weapon
	lda wpn_fire_ms_lo,x
	sta wpn_fire_ms_l
	lda wpn_fire_ms_hi,x
	sta wpn_fire_ms_h
	lda #0
	sta muzzle_ms_l
	sta muzzle_ms_h
	sta fire_rpt_l
	sta fire_rpt_h
	sta mg_frame
	sta wpn_pose
	jmp setup_weapon
.sw_done
	rts

; X = weapon id. Own it; switch to it if this is the first time.
give_weapon
	lda wpn_own_bit,x
	ora owned_weapons
	cmp owned_weapons
	beq .gw_had
	sta owned_weapons
	jmp switch_weapon
.gw_had
	rts

init_weapon
	lda #0
	sta wpn_visible
	sta muzzle_ms_l
	sta muzzle_ms_h
	sta fire_rpt_l
	sta fire_rpt_h
	sta mg_frame
	sta wpn_pose
	lda #$ff
	sta cur_weapon
	ldx #WPN_PISTOL
	jmp switch_weapon		; stay hidden until first swap_view

show_weapon
	lda #$ff
	sta wpn_visible
	rts

; After level reload — keep ownership; re-apply sprite setup
; Leave hidden; main_loop shows after the next frame flips.
refresh_weapon
	lda #0
	sta muzzle_ms_l
	sta muzzle_ms_h
	sta fire_rpt_l
	sta fire_rpt_h
	sta mg_frame
	sta wpn_pose
	ldx cur_weapon
	cpx #$ff
	bne .rw_setup
	ldx #WPN_PISTOL
.rw_setup
	lda #$ff
	sta cur_weapon			; force switch_weapon to re-apply
	jsr switch_weapon
	jmp hide_weapon

hide_weapon
	lda #0
	sta wpn_visible
	rts

; Raster ~88: blit staged snapshot (or hide). Faces stay programmed by
; mux_hud_spr; do not poke $d015 from the main thread. A/X/Y only.
wpn_mux_restore
	lda $d011
	and #%00010000
	beq .wmr_skip				; load / first paint: leave $d015
	lda wpn_visible
	beq .wmr_off
	lda #0
	sta $d01c
	sta $d010
	lda #$ff
	sta $d01d
	sta $d017
	ldx #7
.wmr_ptr
	lda wpn_snap_ptr,x
	sta $43f8,x
	sta $47f8,x
	dex
	bpl .wmr_ptr
	ldx #7
.wmr_col
	lda wpn_snap_col,x
	sta $d027,x
	dex
	bpl .wmr_col
	ldx #15
.wmr_xy
	lda wpn_snap_xy,x
	sta $d000,x
	dex
	bpl .wmr_xy
	lda spr_en
	sta $d015
.wmr_skip
	rts
.wmr_off
	lda #0
	sta $d015
	rts

; A = enable mask → spr_en. $d015 is applied at the weapon raster.
.wpn_en
	sta spr_en
	rts

; A = sprite pointer, Y = sprite index — snapshot; IRQ copies both matrices
.wpn_ptr
	sta wpn_snap_ptr,y
	rts

; Main thread only (weapon switch). Fills wpn_snap_* + spr_en; no VIC.
setup_weapon
	ldx cur_weapon
	lda wpn_body_ptr0,x
	sta wpn_t0
	lda wpn_nbody,x
	sta wpn_t1
	ldy #0
.su_ptr
	tya
	clc
	adc wpn_t0
	jsr .wpn_ptr
	iny
	cpy wpn_t1
	bcc .su_ptr

	lda cur_weapon
	asl
	asl
	asl
	sta wpn_t2
	ldy #0
.su_col
	tya
	clc
	adc wpn_t2
	tax
	lda wpn_spr_col,x
	sta wpn_snap_col,y
	iny
	cpy wpn_t1
	bcc .su_col

	ldx cur_weapon
	lda wpn_nflash,x
	beq .su_pose
	lda wpn_nbody,x
	tay
	lda #1
	sta wpn_snap_col,y
	iny
	lda wpn_nflash,x
	sec
	sbc #1
	beq .su_fptrs
	sta wpn_t0
	lda #10
.su_fred
	sta wpn_snap_col,y
	iny
	dec wpn_t0
	bne .su_fred
.su_fptrs
	jsr .set_flash_ptrs
.su_pose
	jmp apply_pose

.set_flash_ptrs
	ldx cur_weapon
	lda wpn_nflash,x
	beq .sfp_rts
	sta wpn_t1
	lda wpn_nbody,x
	sta wpn_t2
	lda wpn_flash_ptr0,x
	cpx #WPN_CHAINGUN
	bne .sfp_base
	ldy mg_frame
	beq .sfp_base
	lda wpn_flash_ptr1,x
.sfp_base
	sta wpn_t0
	ldy #0
.sfp_loop
	tya
	clc
	adc wpn_t0
	sty wpn_t3
	ldy wpn_t2
	jsr .wpn_ptr
	inc wpn_t2
	ldy wpn_t3
	iny
	cpy wpn_t1
	bcc .sfp_loop
.sfp_rts
	rts

apply_pose
	jsr .apply_xy
	ldx cur_weapon
	lda wpn_pose
	cmp #POSE_FIRE
	bne .ap_body
	lda wpn_nflash,x
	beq .ap_body
	lda wpn_en_fire,x
	jmp .wpn_en
.ap_body
	lda wpn_en_body,x
	jmp .wpn_en

.apply_xy
	lda cur_weapon
	asl
	clc
	adc cur_weapon
	clc
	adc wpn_pose
	tay
	lda wpn_pose_dx,y
	sta wpn_t0
	lda wpn_pose_dy,y
	sta wpn_t1
	ldx cur_weapon
	lda wpn_nbody,x
	sta wpn_t3
	lda cur_weapon
	asl
	asl
	asl
	sta wpn_t2
	ldy #0
.axy_body
	tya
	asl
	tax
	sty wpn_t4
	tya
	clc
	adc wpn_t2
	tay
	lda wpn_spr_x,y
	clc
	adc wpn_t0
	sta wpn_snap_xy,x
	lda wpn_spr_y,y
	clc
	adc wpn_t1
	sta wpn_snap_xy+1,x
	ldy wpn_t4
	iny
	cpy wpn_t3
	bcc .axy_body

	ldx cur_weapon
	lda wpn_nflash,x
	beq .axy_rts
	sta wpn_t3
	lda wpn_nbody,x
	sta wpn_t5
	lda cur_weapon
	asl
	asl
	asl
	sta wpn_t2
	cpx #WPN_CHAINGUN
	bne .axy_flash
	lda mg_frame
	beq .axy_flash
	clc
	lda wpn_t2
	adc #4
	sta wpn_t2
.axy_flash
	ldy #0
.axy_floop
	tya
	clc
	adc wpn_t5
	asl
	tax
	sty wpn_t4
	tya
	clc
	adc wpn_t2
	tay
	lda wpn_flash_x,y
	clc
	adc wpn_t0
	sta wpn_snap_xy,x
	lda wpn_flash_y,y
	clc
	adc wpn_t1
	sta wpn_snap_xy+1,x
	ldy wpn_t4
	iny
	cpy wpn_t3
	bcc .axy_floop
.axy_rts
	rts

.fire_shot
	ldx cur_weapon
	beq .fs_do				; knife — no ammo
	lda player_ammo
	bne .fs_do
	rts					; empty — no fire
.fs_do
	lda #POSE_FIRE
	sta wpn_pose
	lda #<MUZZLE_MS
	sta muzzle_ms_l
	lda #>MUZZLE_MS
	sta muzzle_ms_h
	jsr .set_flash_ptrs
	jsr apply_pose
	ldx cur_weapon
	cpx #WPN_CHAINGUN
	bne .fs_snd
	lda mg_frame
	eor #1
	sta mg_frame
.fs_snd
	ldx cur_weapon
	lda wpn_sound,x
	jsr play_sound
	lda cur_weapon
	beq .fs_knife
	dec player_ammo
	lda #UI_DIRTY_AMMO
	ora ui_dirty
	sta ui_dirty
	jmp gun_attack
.fs_knife
	jmp knife_attack

.muzzle_expired
	lda #0
	sta muzzle_ms_l
	sta muzzle_ms_h
	lda wpn_pose
	cmp #POSE_FIRE
	bne .me_idle
	lda cur_weapon
	beq .me_idle
	lda #POSE_RECOIL
	sta wpn_pose
	lda #<RECOIL_MS
	sta muzzle_ms_l
	lda #>RECOIL_MS
	sta muzzle_ms_h
	jmp apply_pose
.me_idle
	lda #POSE_IDLE
	sta wpn_pose
	jmp apply_pose

update_weapon
	lda key_wpn_knife
	beq .uw_pis
	ldx #WPN_KNIFE
	jsr switch_weapon
.uw_pis
	lda key_wpn_pistol
	beq .uw_mg
	ldx #WPN_PISTOL
	jsr switch_weapon
.uw_mg
	lda key_wpn_mg
	beq .uw_cg
	ldx #WPN_MG
	jsr switch_weapon
.uw_cg
	lda key_wpn_chaingun
	beq .uw_muzzle
	ldx #WPN_CHAINGUN
	jsr switch_weapon

.uw_muzzle
	lda muzzle_ms_l
	ora muzzle_ms_h
	beq .uw_keys
	sec
	lda muzzle_ms_l
	sbc dt_ms
	sta muzzle_ms_l
	lda muzzle_ms_h
	sbc #0
	sta muzzle_ms_h
	bcc .uw_expired
	ora muzzle_ms_l
	bne .uw_keys
.uw_expired
	jsr .muzzle_expired

.uw_keys
	; Tick fire_rpt every frame (wall dt), not only while key_fire — otherwise
	; SuperCPU gaps between IRQ samples freeze the cooldown after one shot.
	lda fire_rpt_l
	ora fire_rpt_h
	beq .uw_chk
	sec
	lda fire_rpt_l
	sbc dt_ms
	sta fire_rpt_l
	lda fire_rpt_h
	sbc #0
	sta fire_rpt_h
	bcs .uw_chk
	lda #0
	sta fire_rpt_l
	sta fire_rpt_h
.uw_chk
	lda key_fire
	beq .uw_up
	lda fire_rpt_l
	ora fire_rpt_h
	bne .uw_done
.uw_shot
	jsr .fire_shot
	lda wpn_fire_ms_l
	sta fire_rpt_l
	lda wpn_fire_ms_h
	sta fire_rpt_h
.uw_done
	rts
.uw_up
	lda wpn_pose
	cmp #POSE_FIRE
	bne .uw_up_rts
	lda muzzle_ms_l
	ora muzzle_ms_h
	bne .uw_up_rts
	jmp .muzzle_expired
.uw_up_rts
	rts

; Locode snapshot + scratch (tape BSS is full). IRQ blits ptr/col/xy to VIC.
wpn_snap_ptr
	!fill 8, 0
wpn_snap_col
	!fill 8, 0
wpn_snap_xy
	!fill 16, 0
wpn_t0	!byte 0
wpn_t1	!byte 0
wpn_t2	!byte 0
wpn_t3	!byte 0
wpn_t4	!byte 0
wpn_t5	!byte 0

