; World items — init / X-sorted cull (SoA x,y,frm,flags live in locode BSS)
!zone items

; MAX_ITEMS in mem.asm
IF_ACTIVE	= $01

T_AMMO		= 18
T_FIRSTAID	= 19
T_FOOD		= 20
T_GOLD_KEY	= 21
T_SILVER_KEY	= 22
; 23 cross / 24 chalice — no packed art
T_MACHINEGUN	= 25
T_PILLAR	= 32
T_TABLE		= 33
T_LAMP		= 34
T_BLOOD		= 35
T_PLANT		= 36

; tile 18..25 → frame ($ff = skip)
item_frm_18
	!byte IF_AMMO_CLIP, IF_FIRSTAID, IF_FOOD, IF_KEY_GOLD, IF_KEY_SILVER
	!byte $ff, $ff, IF_MACHINEGUN
; tile 32..36 → frame
item_frm_32
	!byte IF_URN, IF_TABLE_CHAIRS, IF_CHANDELIER, IF_GIBS, IF_TREE

; ---------------------------------------------------------------------------
items_init
	lda #0
	sta item_count
	tax
.ii_clr
	sta item_flags,x
	inx
	cpx #MAX_ITEMS
	bne .ii_clr

	lda #<MAP
	sta tmp0
	lda #>MAP
	sta tmp1
	lda #0
	sta tmp2				; x
	sta tmp3				; y
.ii_loop
	ldy #0
	lda (tmp0),y
	sta tmp4				; tile
	cmp #T_AMMO
	bcc .ii_next
	cmp #T_MACHINEGUN + 1
	bcc .ii_pick18
	cmp #T_PILLAR
	bcc .ii_next
	cmp #T_PLANT + 1
	bcs .ii_next
	sec
	sbc #T_PILLAR
	tay
	lda item_frm_32,y
	jmp .ii_have
.ii_pick18
	sec
	sbc #T_AMMO
	tay
	lda item_frm_18,y
.ii_have
	cmp #$ff
	beq .ii_next
	ldx item_count
	cpx #MAX_ITEMS
	bcs .ii_next
	sta item_frm,x
	lda tmp2
	sta item_x,x
	lda tmp3
	sta item_y,x
	lda #IF_ACTIVE
	sta item_flags,x
	inx
	stx item_count
.ii_next
	inc tmp0
	bne +
	inc tmp1
+
	inc tmp2
	lda tmp2
	cmp #64
	bne .ii_loop
	lda #0
	sta tmp2
	inc tmp3
	lda tmp3
	cmp #64
	bne .ii_loop

	; sort SoA by item_x ascending
	ldx #1
.is_outer
	cpx item_count
	bcs .is_done
	lda item_x,x
	sta tmp0
	lda item_y,x
	sta tmp1
	lda item_frm,x
	sta tmp2
	lda item_flags,x
	sta tmp3
	stx tmp5
	txa
	tay
.is_inner
	dey
	bmi .is_at0
	lda item_x,y
	cmp tmp0
	bcc .is_place
	beq .is_place
	lda item_x,y
	sta item_x+1,y
	lda item_y,y
	sta item_y+1,y
	lda item_frm,y
	sta item_frm+1,y
	lda item_flags,y
	sta item_flags+1,y
	jmp .is_inner
.is_at0
	lda tmp0
	sta item_x
	lda tmp1
	sta item_y
	lda tmp2
	sta item_frm
	lda tmp3
	sta item_flags
	jmp .is_next
.is_place
	iny
	lda tmp0
	sta item_x,y
	lda tmp1
	sta item_y,y
	lda tmp2
	sta item_frm,y
	lda tmp3
	sta item_flags,y
.is_next
	ldx tmp5
	inx
	cpx item_count
	bcc .is_outer
.is_done
	rts

; ---------------------------------------------------------------------------
; Append near items to vis_slot as index|$80.
; 6×6 AABB centered at player + 3·forward (fwd = cos, −sin; AMP=64 → ×3>>6).
ITEM_GATHER_HALF	= 3			; [c-3 .. c+2] = 6 tiles

items_cull_near
	lda #0
	sta item_considered
	lda item_count
	bne +
	rts
+
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

	; x0 = cx - 3, x1 = cx + 2 (inclusive 6-wide)
	lda tmp4
	sec
	sbc #ITEM_GATHER_HALF
	bcs +
	lda #0
+
	sta tmp0				; x0
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
	sta tmp1				; x1

	lda tmp5
	sec
	sbc #ITEM_GATHER_HALF
	bcs +
	lda #0
+
	sta tmp2				; y0
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
	sta tmp3				; y1

	ldx #0
.ic_skip
	cpx item_count
	bcs .ic_done
	lda item_x,x
	cmp tmp0
	bcs .ic_band
	inx
	bne .ic_skip
.ic_band
	cpx item_count
	bcs .ic_done
	lda item_x,x
	cmp tmp1
	beq .ic_iny
	bcs .ic_done
.ic_iny
	lda item_flags,x
	and #IF_ACTIVE
	beq .ic_n
	lda item_y,x
	cmp tmp2
	bcc .ic_n
	cmp tmp3
	beq +
	bcs .ic_n
+
	ldy vis_count
	cpy #MAX_VIS
	bcs .ic_done
	txa
	ora #$80
	sta vis_slot,y
	iny
	sty vis_count
	inc item_considered
.ic_n
	inx
	bne .ic_band
.ic_done
	rts
