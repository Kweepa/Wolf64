; World items — map AABB cull / pickup (per-frame scratch in SFX→enemy gap)
!zone items

T_FLOOR		= 18
T_AMMO		= 19
T_FIRSTAID	= 20
T_FOOD		= 21
T_GOLD_KEY	= 22
T_SILVER_KEY	= 23
; 24 cross / 25 chalice — no packed art
T_MACHINEGUN	= 26
T_CHAINGUN	= 27
T_HANGED	= 28
T_WELL		= 29
T_FLAG		= 30
T_PUDDLE	= 31
T_BED		= 32
T_PILLAR	= 33
T_TABLE		= 34
T_LAMP		= 35
T_BLOOD		= 36
T_PLANT		= 37
T_DOGFOOD	= 38
T_CEIL_LIGHT	= 39
T_CAGE		= 40

; tile 19..32 → frame ($ff = skip)
item_frm_19
	!byte IF_AMMO_CLIP, IF_FIRSTAID, IF_FOOD, IF_KEY_GOLD, IF_KEY_SILVER
	!byte $ff, $ff, IF_MACHINEGUN, IF_CHAINGUN
	!byte IF_HANGED_MAN, IF_WELL, IF_FLAG, IF_PUDDLE, IF_BED
; tile 33..40 → frame
item_frm_33
	!byte IF_URN, IF_TABLE_CHAIRS, IF_CHANDELIER, IF_GIBS, IF_TREE
	!byte IF_DOG_FOOD, IF_CEILING_LIGHT, IF_SKELETON_CAGE

; A = map tile → A = frame, or $ff if not a drawable/collectible item
item_tile_frm
	cmp #T_AMMO
	bcc .itf_no
	cmp #T_BED + 1
	bcc .itf_pick
	cmp #T_CAGE + 1
	bcs .itf_no
	sec
	sbc #T_PILLAR
	tay
	lda item_frm_33,y
	rts
.itf_pick
	sec
	sbc #T_AMMO
	tay
	lda item_frm_19,y
	rts
.itf_no
	lda #$ff
	rts

; ---------------------------------------------------------------------------
; Walk-over collectibles at player tile (props left in place)
items_try_pickup
	lda playerx_h
	sta tmp0
	lda playery_h
	sta tmp1
	jsr map_to_tile
	ldy #0
	lda (tile_l),y
	jsr item_tile_frm
	bmi .itp_rts				; not an item / no art
	jsr item_apply
	bcc .itp_rts				; prop or full inventory
	lda #T_FLOOR
	ldy #0
	sta (tile_l),y
.itp_rts
	rts

; A = frame id. C=1 if collected (clear map), C=0 leave tile
item_apply
	cmp #IF_KEY_GOLD
	bne .ia_sil
	lda player_keys
	ora #KEY_GOLD
	sta player_keys
	lda #UI_DIRTY_KEYS
	ora ui_dirty
	sta ui_dirty
	lda #SOUND_GETKEY
	jsr play_sound
	sec
	rts
.ia_sil
	cmp #IF_KEY_SILVER
	bne .ia_food
	lda player_keys
	ora #KEY_SILVER
	sta player_keys
	lda #UI_DIRTY_KEYS
	ora ui_dirty
	sta ui_dirty
	lda #SOUND_GETKEY
	jsr play_sound
	sec
	rts
.ia_food
	cmp #IF_FOOD
	bne .ia_dog
	lda player_hp
	cmp #HP_MAX
	bcc +
	jmp .ia_no				; full — leave food
+
	lda #SOUND_HEALTH1
	jsr play_sound
	lda #FOOD_HP_AMT
	jmp item_add_hp
.ia_dog
	cmp #IF_DOG_FOOD
	bne .ia_aid
	lda player_hp
	cmp #HP_MAX
	bcc +
	jmp .ia_no
+
	lda #SOUND_HEALTH1
	jsr play_sound
	lda #DOGFOOD_HP_AMT
	jmp item_add_hp
.ia_aid
	cmp #IF_FIRSTAID
	bne .ia_guts
	lda player_hp
	cmp #HP_MAX
	bcc +
	jmp .ia_no				; full — leave kit
+
	lda #SOUND_HEALTH2
	jsr play_sound
	lda #FIRSTAID_HP_AMT
	jmp item_add_hp
.ia_guts
	cmp #IF_GIBS
	bne .ia_ammo
	lda player_hp
	cmp #GUTS_HP_MAX + 1
	bcc +
	jmp .ia_no				; >10% — leave guts
+
	lda #SOUND_HEALTH1
	jsr play_sound
	lda #GUTS_HP_AMT
	jmp item_add_hp
.ia_ammo
	cmp #IF_AMMO_CLIP
	bne .ia_mg
	lda player_ammo
	cmp #AMMO_MAX
	bcc +
	jmp .ia_no				; full — leave clip
+
	jsr ammo_clip_amt
	lda #UI_DIRTY_AMMO
	ora ui_dirty
	sta ui_dirty
	lda #SOUND_GETAMMO
	jsr play_sound
	sec
	rts
.ia_mg
	cmp #IF_MACHINEGUN
	bne .ia_cg
	ldx #WPN_MG
	jmp item_take_gun
.ia_cg
	cmp #IF_CHAINGUN
	bne .ia_no
	ldx #WPN_CHAINGUN
	; fall through

; X = weapon. First pickup switches to it; already owned + full ammo → leave.
item_take_gun
	lda wpn_own_bit,x
	bit owned_weapons
	beq .itg_take
	lda player_ammo
	cmp #AMMO_MAX
	bcc .itg_take
	clc
	rts
.itg_take
	jsr give_weapon
	lda player_ammo
	cmp #AMMO_MAX
	bcs .itg_wep
	jsr ammo_clip_amt
	lda #UI_DIRTY_AMMO
	ora ui_dirty
	sta ui_dirty
.itg_wep
	lda #SOUND_GETMACHINE
	jsr play_sound
	sec
	rts
.ia_no
	clc
	rts

; A = heal amount. Caller already checked HP < HP_MAX.
item_add_hp
	clc
	adc player_hp
	bcs .iah_sat
	cmp #HP_MAX + 1
	bcc .iah_ok
.iah_sat
	lda #HP_MAX
.iah_ok
	sta player_hp
	lda #UI_DIRTY_HP | UI_DIRTY_FACE
	ora ui_dirty
	sta ui_dirty
	sec
	rts

; ---------------------------------------------------------------------------
; Scan map AABB → per-frame item_x/y/frm scratch + vis_slot (vis_kind=1).
; 6×6 centered at player + 3·forward (fwd = cos, −sin; AMP=64 → ×3>>6).
ITEM_GATHER_HALF	= 3			; [c-3 .. c+2] = 6 tiles

items_cull_near
	lda #0
	sta item_considered

	; cx = playerx_h + (costab[playera]*3)>>6
	ldy playera
	lda costab,y
	jsr item_dir_tiles
	clc
	adc playerx_h
	jsr item_clamp63
	pha					; cx
	; cy = playery_h + (−sintab*3)>>6
	ldy playera
	lda sintab,y
	jsr neg_a
	jsr item_dir_tiles
	clc
	adc playery_h
	jsr item_clamp63
	sta tmp5				; cy
	pla
	sta tmp4				; cx

	; x0/x1/y0/y1 — stash in e_* (free until depth pass)
	lda tmp4
	sec
	sbc #ITEM_GATHER_HALF
	bcs +
	lda #0
+
	sta e_dx_l				; x0
	lda tmp4
	clc
	adc #ITEM_GATHER_HALF - 1
	bcc +
	lda #63
+
	cmp #64
	bcc +
	lda #63
+
	sta e_dx_h				; x1

	lda tmp5
	sec
	sbc #ITEM_GATHER_HALF
	bcs +
	lda #0
+
	sta e_dy_l				; y0
	lda tmp5
	clc
	adc #ITEM_GATHER_HALF - 1
	bcc +
	lda #63
+
	cmp #64
	bcc +
	lda #63
+
	sta e_dy_h				; y1

	lda #0
	sta tmp4				; scratch index

	lda e_dx_l
	sta tmp0
	sta tmp2				; x
	lda e_dy_l
	sta tmp1
	sta tmp3				; y
	jsr map_to_tile
	lda tile_l
	sta e_acc_l				; row base (x0)
	lda tile_h
	sta e_acc_h
.ic_x
	ldy #0
	lda (tile_l),y
	jsr item_tile_frm
	bmi .ic_next
	ldy vis_count
	cpy #MAX_VIS
	bcs .ic_done
	ldx tmp4
	sta item_frm,x
	lda tmp2
	sta item_x,x
	lda tmp3
	sta item_y,x
	txa
	sta vis_slot,y
	lda #1				; VK_ITEM
	sta vis_kind,y
	iny
	sty vis_count
	inc tmp4
	inc item_considered
.ic_next
	lda tmp2
	cmp e_dx_h
	bcs .ic_ynext
	inc tmp2
	inc tile_l
	bne .ic_x
	inc tile_h
	jmp .ic_x
.ic_ynext
	lda tmp3
	cmp e_dy_h
	bcs .ic_done
	inc tmp3
	clc
	lda e_acc_l
	adc #64
	sta e_acc_l
	sta tile_l
	lda e_acc_h
	adc #0
	sta e_acc_h
	sta tile_h
	lda e_dx_l
	sta tmp2
	jmp .ic_x
.ic_done
	rts
