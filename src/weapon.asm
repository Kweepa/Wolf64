; Pistol + chaingun HUD (SquareDoom layers / muzzle flash)
; Sprite banks in VIC bank 1 @ $4800 (see wolf64.asm). Pointers written to
; both matrix sprite-pointer slots ($43f8 / $47f8) for double-buffer.
!zone weapon

PISTOL_SPR_PTR0 = (PISTOL_SPRITES - SCREEN) / 64
MINIGUN_B_SPR_PTR0 = (MINIGUN_B_SPRITES - SCREEN) / 64
MINIGUN_SPR_PTR0 = (MINIGUN_SPRITES - SCREEN) / 64
MUZZLE_FLASH_PTR0 = (MUZZLE_FLASH_SPRITES - SCREEN) / 64

WPN_PISTOL = 0
WPN_CHAINGUN = 1

EIGHT_ENABLE_IDLE = $3f		; sprites 0–5 (flash 6–7 off)
FLASH_ENABLE = $c0			; sprites 6–7
MUZZLE_MS = 300

; Screen layout (XY expand): sprite px ×2. Bottom hand row Y=208.
; VIC: low sprite # = front — body first, muzzle flash last.

muzzle_hi_col	!byte 1
muzzle_hi_cols
	!byte 1, 7, 1, 10

; Fire interval (ms while held) — pistol, chaingun
wpn_fire_ms_lo
	!byte <600, <100
wpn_fire_ms_hi
	!byte >600, >100

wpn_setup_lo
	!byte <setup_pistol, <setup_chaingun
wpn_setup_hi
	!byte >setup_pistol, >setup_chaingun

; Ownership bits: bit0 pistol, bit1 chaingun
wpn_own_bit
	!byte $01, $02

; SMC — +1/+2 patched by switch_weapon
wpn_setup
	jmp setup_pistol

pistol_spr_col
	!byte 15, 11, 0			; gun hilight / dark grey / black
	!byte 8, 9, 0			; hand orange / brown / black
	!byte 1, 2				; flash white, red
pistol_spr_x
	!byte 160, 160, 160
	!byte 160, 160, 160
	!byte 166, 166
pistol_spr_y
	!byte 186, 186, 186
	!byte 208, 208, 208
	!byte 162, 162

chaingun_spr_col
	!byte 15, 15			; upper / lower highlights
	!byte 11, 11			; grey body L/R
	!byte 0, 0				; black body L/R
	!byte 1, 2				; flash white, red
chaingun_spr_x
	!byte 160, 160
	!byte 136, 184
	!byte 136, 184
	!byte 160, 160
chaingun_spr_y
	!byte 194, 208
	!byte 194, 194
	!byte 208, 208
	!byte 172, 172

; X = weapon id. Gated by owned_weapons.
switch_weapon
	lda wpn_own_bit,x
	bit owned_weapons
	beq .sw_done
	cpx cur_weapon
	beq .sw_done
	stx cur_weapon
	lda wpn_setup_lo,x
	sta wpn_setup + 1
	lda wpn_setup_hi,x
	sta wpn_setup + 2
	lda wpn_fire_ms_lo,x
	sta wpn_fire_ms_l
	lda wpn_fire_ms_hi,x
	sta wpn_fire_ms_h
	lda #0
	sta muzzle_ms_l
	sta muzzle_ms_h
	sta fire_rpt_l
	sta fire_rpt_h
	jsr wpn_setup
	jmp .wpn_hi_bright
.sw_done
	rts

init_weapon
	lda #0
	sta wpn_visible
	sta $d015
	sta muzzle_ms_l
	sta muzzle_ms_h
	sta fire_rpt_l
	sta fire_rpt_h
	sta mg_frame
	sta muzzle_flash_var
	sta muzzle_hi_cycle
	lda #$03				; pistol + chaingun from the start
	sta owned_weapons
	lda #$ff
	sta cur_weapon			; force setup
	ldx #WPN_PISTOL
	jsr switch_weapon
	; fall through — show immediately
show_weapon
	lda #$ff
	sta wpn_visible
	lda spr_en
	sta $d015
	; fall through
.wpn_hi_bright
	lda muzzle_ms_l
	ora muzzle_ms_h
	beq .wh_idle
	lda muzzle_hi_col
	bne .wh_apply
.wh_idle
	lda #15				; light grey highlight (no sector lighting yet)
.wh_apply
	sta $d027
	ldx cur_weapon
	cpx #WPN_CHAINGUN
	bne .wh_rts
	sta $d028
.wh_rts
	rts

hide_weapon
	lda #0
	sta wpn_visible
	sta $d015
	rts

; A = enable mask → spr_en; $d015 only if wpn_visible.
.wpn_en
	sta spr_en
	and wpn_visible
	sta $d015
	rts

; A = sprite pointer, X = sprite index — both double-buffer matrices
.wpn_ptr
	sta $43f8,x
	sta $47f8,x
	rts

setup_pistol
	lda #EIGHT_ENABLE_IDLE
	jsr .wpn_en
	lda #$ff
	sta $d01d
	sta $d017
	lda #0
	sta $d01c
	sta $d010
	ldx #0
	ldy #0
	clc
.sp_set
	lda pistol_spr_col,x
	sta $d027,x
	cpx #6
	bcs .sp_xy
	txa
	adc #PISTOL_SPR_PTR0
	jsr .wpn_ptr
.sp_xy
	lda pistol_spr_x,x
	sta $d000,y
	lda pistol_spr_y,x
	sta $d001,y
	iny
	iny
	inx
	cpx #8
	bcc .sp_set
	jmp .set_muzzle_ptrs

setup_chaingun
	lda #0
	sta mg_frame
	lda #EIGHT_ENABLE_IDLE
	jsr .wpn_en
	lda #$ff
	sta $d01d
	sta $d017
	lda #0
	sta $d01c
	sta $d010
	ldx #0
	ldy #0
	clc
.sm_set
	lda chaingun_spr_col,x
	sta $d027,x
	cpx #6
	bcs .sm_xy
	txa
	adc #MINIGUN_SPR_PTR0
	jsr .wpn_ptr
.sm_xy
	lda chaingun_spr_x,x
	sta $d000,y
	lda chaingun_spr_y,x
	sta $d001,y
	iny
	iny
	inx
	cpx #8
	bcc .sm_set
	jmp .set_muzzle_ptrs

.set_muzzle_ptrs
	lda muzzle_flash_var
	and #1
	asl
	clc
	adc #MUZZLE_FLASH_PTR0
	ldx #6
	jsr .wpn_ptr
	clc
	adc #1
	ldx #7
	jmp .wpn_ptr

; Chaingun body A/B → VIC 0 (upper), 2–3 (grey L/R). Shared 1/4/5 unchanged.
.set_chaingun_frame_ptrs
	lda mg_frame
	bne .smfp_b
	lda #MINIGUN_SPR_PTR0
	ldx #0
	jsr .wpn_ptr
	lda #MINIGUN_SPR_PTR0 + 2
	ldx #2
	jsr .wpn_ptr
	lda #MINIGUN_SPR_PTR0 + 3
	ldx #3
	jmp .wpn_ptr
.smfp_b
	lda #MINIGUN_B_SPR_PTR0
	ldx #0
	jsr .wpn_ptr
	lda #MINIGUN_B_SPR_PTR0 + 1
	ldx #2
	jsr .wpn_ptr
	lda #MINIGUN_B_SPR_PTR0 + 2
	ldx #3
	jmp .wpn_ptr

.fire_shot
	lda #<MUZZLE_MS
	sta muzzle_ms_l
	lda #>MUZZLE_MS
	sta muzzle_ms_h
	jsr .set_muzzle_ptrs
	inc muzzle_flash_var
	ldx cur_weapon
	cpx #WPN_CHAINGUN
	bne .fs_flash_en
	lda mg_frame
	eor #1
	sta mg_frame
	jsr .set_chaingun_frame_ptrs
.fs_flash_en
	lda spr_en
	ora #FLASH_ENABLE
	jsr .wpn_en
	inc muzzle_hi_cycle
	lda muzzle_hi_cycle
	and #3
	tax
	lda muzzle_hi_cols,x
	sta muzzle_hi_col
	jmp .wpn_hi_bright

; Per frame after render: muzzle timeout + fire while SPACE held + weapon keys.
update_weapon
	lda key_wpn_pistol
	beq .uw_cg
	ldx #WPN_PISTOL
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
	lda #0
	sta muzzle_ms_l
	sta muzzle_ms_h
	jsr wpn_setup
	jsr .wpn_hi_bright

.uw_keys
	lda key_fire
	beq .uw_up
	lda fire_rpt_l
	ora fire_rpt_h
	beq .uw_shot
	sec
	lda fire_rpt_l
	sbc dt_ms
	sta fire_rpt_l
	lda fire_rpt_h
	sbc #0
	sta fire_rpt_h
	bcs .uw_done
.uw_shot
	jsr .fire_shot
	lda wpn_fire_ms_l
	sta fire_rpt_l
	lda wpn_fire_ms_h
	sta fire_rpt_h
.uw_done
	rts
.uw_up
	lda #0
	sta fire_rpt_l
	sta fire_rpt_h
	lda cur_weapon
	cmp #WPN_CHAINGUN
	bne .uw_up_rts
	lda mg_frame
	beq .uw_up_rts
	lda #0
	sta mg_frame
	jsr .set_chaingun_frame_ptrs
.uw_up_rts
	rts
