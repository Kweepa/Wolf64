; F1 automap — 38×20 square cells in the 3D viewport (cols 1–38, rows 5–24).
; Fog: map_visited, 128 bytes at the end of GAME_STATE (one bit = 2×2 tiles).
!zone mapscreen

MAP_SX_MAX	= 26			; 64 - 38
MAP_SY_MAX	= 44			; 64 - 20
MAP_COL_FLOOR	= $0c			; grey
MAP_COL_DOOR	= $03			; cyan
MAP_COL_GOLD	= $07			; yellow key door

; ------------------------------------------------------------------
; map_clear / map_reveal / map_reset
; ------------------------------------------------------------------
map_clear
	ldx #0
	lda #0
.mc
	sta map_visited,x
	inx
	bpl .mc				; X = 0..127
	rts

; Stamp the 5×5 of map cells around the player. A set bit shows the whole 2×2.
map_reveal
	ldx #0
.rv_y
	lda playery_h
	clc
	adc map_ofs,x
	cmp #64
	bcs .rv_ny
	sta mapy
	ldy #0
.rv_x
	lda playerx_h
	clc
	adc map_ofs,y
	cmp #64
	bcs .rv_nx
	sta mapx
	txa
	pha
	tya
	pha
	jsr map_visit_xy
	pla
	tay
	pla
	tax
.rv_nx
	iny
	cpy #5
	bne .rv_x
.rv_ny
	inx
	cpx #5
	bne .rv_y
	rts

map_reset
	pha
	jsr map_clear
	jsr map_reveal
	pla
	rts

; mapx/mapy → set that cell's coarse bit. Clobbers A/X/Y/tmp2.
map_visit_xy
	lda mapy
	lsr
	asl
	asl
	sta tmp2			; (y>>1)*4
	lda mapx
	lsr
	pha
	and #7
	tax
	pla
	lsr
	lsr
	lsr
	clc
	adc tmp2
	tay
	lda map_bit,x
	ora map_visited,y
	sta map_visited,y
	rts

map_ofs
	!byte $fe, $ff, 0, 1, 2
map_bit
	!byte $01, $02, $04, $08, $10, $20, $40, $80

; ------------------------------------------------------------------
; map_f1_down — C=1 when F1 is down and SPACE-column PB4 is still up.
; 1351 LMB grounds PB4 on every column. F1 (PA0/PB4) counts only when
; the SPACE column (PA7/PB4) reads released. Same test as SquareDoom.
; ------------------------------------------------------------------
map_f1_down
	ldy #$fe			; F1 column
	jsr map_cia_read
	and #$10
	bne .mfd_up
	ldy #$7f			; SPACE column
	jsr map_cia_read
	and #$10
	beq .mfd_up			; LMB or SPACE
	sec
	rts
.mfd_up
	clc
	rts

; ------------------------------------------------------------------
; map_poll_f1 — rising F1 opens the map. C=1 if the map ran.
; ------------------------------------------------------------------
map_poll_f1
	jsr map_f1_down
	bcc .mp_up
	lda map_f1
	bne .mp_held
	lda #1
	sta map_f1
	jsr mapscreen
	rts
.mp_up
	lda #0
	sta map_f1
.mp_held
	clc
	rts

; ------------------------------------------------------------------
; mapscreen — blocking overlay. Returns C=1 (caller repaints).
; Runs under I/O ($01=$34). CIA and raster go through mapio.asm.
; ------------------------------------------------------------------
mapscreen
	lda wpn_visible
	sta map_wpn_was
	jsr hide_weapon
	lda #1
	sta map_open
	jsr map_clear_latches
	jsr map_wait_frame		; let raster 88 drop the gun
	jsr map_center
	lda #0
	sta map_arrow_on
	jsr map_draw
	jsr map_wait_f1_up
.ms_loop
	jsr map_wait_frame
	jsr map_read_keys
	bcs .ms_exit
	jsr map_apply_scroll
	beq .ms_loop
	jsr map_scroll
	jmp .ms_loop
.ms_exit
	jsr map_arrow_restore
	lda #0
	sta map_open
	jsr map_clear_latches
	jsr map_wait_f1_up
	lda map_wpn_was
	sta wpn_visible
	sec
	rts

map_center
	lda playerx_h
	sec
	sbc #19
	bcs +
	lda #0
+
	cmp #MAP_SX_MAX + 1
	bcc +
	lda #MAP_SX_MAX
+
	sta map_sx
	lda playery_h
	sec
	sbc #9				; screen row 10 after the Y flip
	bcs +
	lda #0
+
	cmp #MAP_SY_MAX + 1
	bcc +
	lda #MAP_SY_MAX
+
	sta map_sy
	rts

map_clear_latches
	sei
	lda #0
	sta in_turn_l
	sta in_turn_r
	sta in_fwd
	sta in_back
	sta in_strafel
	sta in_strafer
	sta in_fire
	sta in_wpn_knife
	sta in_wpn_pistol
	sta in_wpn_mg
	sta in_wpn_chaingun
	cli
	rts

map_wait_f1_up
.wu
	jsr map_wait_frame
	jsr map_f1_down
	bcs .wu				; still held
	lda #0
	sta map_f1
	rts

; C=1 on real F1 rising edge (not LMB). map_keys = WASD (not IJKL).
map_read_keys
	ldy #$fd			; W/A/S column, not I/J/K
	jsr map_cia_read
	eor #$ff
	tax
	and #$02			; W → bit 0
	lsr
	sta map_keys
	txa
	and #$20			; S
	beq +
	lda map_keys
	ora #$02
	sta map_keys
+
	txa
	and #$04			; A
	beq +
	lda map_keys
	ora #$04
	sta map_keys
+
	ldy #$fb
	jsr map_cia_read
	eor #$ff
	and #$04			; D
	beq +
	lda map_keys
	ora #$08
	sta map_keys
+
	jsr map_f1_down
	bcc .rk_up
	lda map_f1
	bne .rk_held
	lda #1
	sta map_f1
	sec
	rts
.rk_up
	lda #0
	sta map_f1
.rk_held
	clc
	rts

; Z=1 if scroll did not change. map_sdir: $01 +Y $02 −Y $04 −X $08 +X.
map_apply_scroll
	lda #0
	sta map_sdir
	lda map_sx
	sta map_osx
	lda map_sy
	sta map_osy
	lda map_sy
	sta tmp4
	lda map_keys
	and #$01			; W: toward +Y (top of the map)
	beq .as_s
	lda map_sy
	cmp #MAP_SY_MAX
	bcs .as_s
	inc map_sy
.as_s
	lda map_keys
	and #$02			; S: toward −Y (bottom of the map)
	beq .as_sy
	lda map_sy
	beq .as_sy
	dec map_sy
.as_sy
	lda map_sy
	cmp tmp4
	beq .as_x0
	lda #$01
	bcs .as_sybit
	lda #$02
.as_sybit
	sta map_sdir
.as_x0
	lda map_sx
	sta tmp4
	lda map_keys
	and #$04
	beq .as_d
	lda map_sx
	beq .as_d
	dec map_sx
.as_d
	lda map_keys
	and #$08
	beq .as_sx
	lda map_sx
	cmp #MAP_SX_MAX
	bcs .as_sx
	inc map_sx
.as_sx
	lda map_sx
	cmp tmp4
	beq .as_z
	lda #$08
	bcs .as_sxbit
	lda #$04
.as_sxbit
	ora map_sdir
	sta map_sdir
.as_z
	lda map_sdir
	rts

; ------------------------------------------------------------------
; Draw viewport into the front matrix. Both nibbles = one 8×8 colour.
; ------------------------------------------------------------------
map_draw
	jsr map_arrow_restore
	jsr set_scr_front
	ldx #0
.md_row
	txa
	pha
	jsr map_paint_viewrow
	pla
	tax
	inx
	cpx #20
	bne .md_row
	jmp map_draw_player

; Shift the viewport one tile and paint the new edge. map_sx/sy already updated.
map_scroll
	jsr set_scr_front
	jsr map_put_under
	ldx #0
.sc1	lda map_sdir
	and map_shmask,x
	beq .sc1n
	lda map_shlo,x
	sta .sc1g+1
	lda map_shhi,x
	sta .sc1g+2
	txa
	pha
.sc1g	jsr $ffff
	pla
	tax
.sc1n	inx
	cpx #4
	bne .sc1
	ldx #0
.sc2	lda map_sdir
	and map_shmask,x
	beq .sc2n
	lda map_edarg,x
	stx tmp4
	cpx #2
	bcs .sc2c
	jsr map_paint_viewrow
	jmp .sc2r
.sc2c	jsr map_paint_col
.sc2r	ldx tmp4
.sc2n	inx
	cpx #4
	bne .sc2
	jmp map_draw_player

map_shmask
	!byte $01, $02, $04, $08
map_edarg
	!byte 0, 19, 1, 38
map_shlo
	!byte <map_shift_down, <map_shift_up, <map_shift_right, <map_shift_left
map_shhi
	!byte >map_shift_down, >map_shift_up, >map_shift_right, >map_shift_left

; Arrow cell is still at the pre-scroll screen spot. Put its tile back.
map_put_under
	lda map_arrow_on
	beq .pu_rts
	lda map_osx
	clc
	adc map_ar_col
	sta mapx
	lda #19
	sec
	sbc map_ar_row
	clc
	adc map_osy
	sta mapy
	jsr map_tile_color
	jsr map_pack_color
	pha
	lda map_ar_row
	clc
	adc #5
	jsr map_row_ptr
	ldy map_ar_col
	iny
	pla
	sta (tmp0),y
	jmp map_arrow_restore
.pu_rts
	rts

; A = dest view row, X = src view row. Columns 1..38. Preserves tmp6.
map_copy_viewrow
	sta tmp5
	txa
	clc
	adc #5
	jsr map_row_ptr
	lda tmp0
	sta aux_l
	lda tmp1
	sta aux_h
	lda tmp5
	clc
	adc #5
	jsr map_row_ptr
	ldy #1
-	lda (aux_l),y
	sta (tmp0),y
	iny
	cpy #39
	bne -
	rts

; +Y: content moves down the screen. Copy from the bottom.
map_shift_down
	ldx #18
-	stx tmp6
	inx
	txa
	ldx tmp6
	jsr map_copy_viewrow
	ldx tmp6
	dex
	bpl -
	rts

; −Y: content moves up. src = dest+1, top first.
map_shift_up
	ldx #0
-	stx tmp6
	inx
	stx tmp5
	lda tmp6
	ldx tmp5
	jsr map_copy_viewrow
	ldx tmp6
	inx
	cpx #19
	bne -
	rts

map_shift_right
	lda #0
	sta tmp4
	beq map_shift_h
map_shift_left
	lda #1
	sta tmp4
map_shift_h
	lda #0
	sta map_row
.sh	lda map_row
	clc
	adc #5
	jsr map_row_ptr
	lda tmp4
	bne .sh_left
	ldy #37
-	lda (tmp0),y
	iny
	sta (tmp0),y
	dey
	dey
	bne -
	beq .sh_nx
.sh_left
	ldy #2
-	lda (tmp0),y
	dey
	sta (tmp0),y
	iny
	iny
	cpy #39
	bne -
.sh_nx	inc map_row
	lda map_row
	cmp #20
	bne .sh
	rts

; A = view row 0..19 (0 = top = map_sy+19).
map_paint_viewrow
	sta map_row
	clc
	adc #5
	jsr map_row_ptr
	lda #19
	sec
	sbc map_row
	clc
	adc map_sy
	sta mapy
	ldy #1
-	tya
	clc
	adc map_sx
	sec
	sbc #1
	sta mapx
	jsr map_tile_color
	jsr map_pack_color
	sta (tmp0),y
	iny
	cpy #39
	bne -
	rts

; A = screen column 1 or 38.
map_paint_col
	sta tmp6
	sec
	sbc #1
	clc
	adc map_sx
	sta mapx
	lda #0
	sta map_row
-	lda map_row
	clc
	adc #5
	jsr map_row_ptr
	lda #19
	sec
	sbc map_row
	clc
	adc map_sy
	sta mapy
	ldy tmp6
	jsr map_tile_color
	jsr map_pack_color
	sta (tmp0),y
	inc map_row
	lda map_row
	cmp #20
	bne -
	rts

; Colour nibble in A → both nibbles in A. Clobbers tmp2.
map_pack_color
	sta tmp2
	asl
	asl
	asl
	asl
	ora tmp2
	rts

; A = screen row → tmp0/tmp1 = scr_front + row*40. Clobbers tmp2/tmp3.
map_row_ptr
	sta tmp2
	lda #0
	sta tmp1
	lda tmp2
	asl
	rol tmp1
	asl
	rol tmp1
	asl
	rol tmp1
	asl
	rol tmp1
	asl
	rol tmp1			; tmp1:A = row*32
	sta tmp3
	lda tmp2
	asl
	asl
	asl				; *8 (row <= 24)
	clc
	adc tmp3
	sta tmp0
	lda tmp1
	adc #0
	sta tmp1
	lda tmp0
	clc
	adc scr_front_l
	sta tmp0
	lda tmp1
	adc scr_front_h
	sta tmp1
	rts

; Colour nibble for mapx/mapy. Preserves tmp0/tmp1 and Y.
map_tile_color
	tya
	pha
	lda mapy
	lsr
	asl
	asl
	sta tmp2
	lda mapx
	lsr
	sta tmp3
	and #7
	tax
	lda tmp3
	lsr
	lsr
	lsr
	clc
	adc tmp2
	tay
	lda map_bit,x
	and map_visited,y
	beq .tc_fog
	lda mapy
	lsr
	lsr
	sta aux_h			; high of mapy*64
	lda mapy
	asl
	asl
	asl
	asl
	asl
	asl
	sta aux_l
	clc
	adc mapx
	sta aux_l
	bcc +
	inc aux_h
+
	lda aux_l
	clc
	adc #<MAP
	sta aux_l
	lda aux_h
	adc #>MAP
	sta aux_h
	ldy #0
	lda (aux_l),y
	cmp #18
	bcs .tc_floor
	cmp #16
	beq .tc_gold			; yellow key door
	cmp #15
	bcs .tc_door			; unlocked + silver
	tax
	lda map_wall_col,x
	bne .tc_out
.tc_floor
	lda #MAP_COL_FLOOR
	bne .tc_out
.tc_door
	lda #MAP_COL_DOOR
	bne .tc_out
.tc_gold
	lda #MAP_COL_GOLD
	bne .tc_out
.tc_fog
	lda #0
.tc_out
	sta tmp3
	pla
	tay
	lda tmp3
	rts

map_draw_player
	lda playerx_h
	sec
	sbc map_sx
	cmp #38
	bcs .dp_off
	sta map_ar_col
	lda playery_h
	sec
	sbc map_sy
	cmp #20
	bcs .dp_off
	sta tmp3
	lda #19
	sec
	sbc tmp3
	sta map_ar_row
	lda #1
	sta map_arrow_on
	lda map_ar_row
	clc
	adc #5
	jsr map_row_ptr
	ldy map_ar_col
	iny
	lda #$10 | MAP_COL_FLOOR	; white arrow, floor-grey ground
	sta (tmp0),y
	jsr map_player_bmp
	lda playera
	clc
	adc #32
	lsr
	lsr
	lsr
	lsr
	lsr
	lsr
	and #3				; 0=E 1=N 2=W 3=S
	asl
	asl
	asl
	tax
	ldy #0
.dp_cp
	lda map_arrow_glyph,x
	sta (aux_l),y
	inx
	iny
	cpy #8
	bne .dp_cp
	rts
.dp_off
	lda #0
	sta map_arrow_on
	rts

map_arrow_restore
	lda map_arrow_on
	beq .ar_rts
	lda #0
	sta map_arrow_on
	jsr map_player_bmp
	ldy #0
	lda #$55
.ar_hi
	sta (aux_l),y
	iny
	cpy #4
	bne .ar_hi
	lda #$aa
.ar_lo
	sta (aux_l),y
	iny
	cpy #8
	bne .ar_lo
.ar_rts
	rts

; aux → bitmap cell for map_ar_row/col (screen row+5, col+1). Clobbers tmp2.
map_player_bmp
	lda map_ar_row
	clc
	adc #5
	sta tmp2
	lda #0
	sta aux_h
	lda tmp2
	asl
	rol aux_h
	asl
	rol aux_h
	asl
	rol aux_h
	asl
	rol aux_h
	asl
	rol aux_h
	asl
	rol aux_h			; aux_h:A = row*64
	sta aux_l
	lda aux_h
	clc
	adc tmp2			; + row*256
	sta aux_h
	lda map_ar_col
	clc
	adc #1
	asl
	asl
	asl				; col*8
	clc
	adc aux_l
	sta aux_l
	bcc +
	inc aux_h
+
	lda aux_l
	clc
	adc #<BITMAP
	sta aux_l
	lda aux_h
	adc #>BITMAP
	sta aux_h
	rts

; 4×8 MCM arrows from textures/maparrows.png (right, up, left, down).
; %01 = white (high nibble), %10 = floor grey (low nibble). Order E, N, W, S.
; +Y is up the screen, so N (−Y) uses the down arrow and S the up arrow.
map_arrow_glyph
	!byte $9a, $9a, $66, $65, $65, $66, $9a, $9a	; E (sheet right)
	!byte $96, $96, $69, $69, $96, $96, $a6, $a6	; N (sheet down)
	!byte $a6, $a6, $99, $59, $59, $99, $a6, $a6	; W (sheet left)
	!byte $9a, $9a, $96, $96, $69, $69, $96, $96	; S (sheet up)

; Texture slot 0..15 → automap colour. Tile id is the slot for walls 1..14.
map_wall_col
	!byte $07, $0b, $02, $06, $0b, $09, $08, $02	; yel, dgry, red, blu, dgry, brn, org, red
	!byte $05, $04, $04, $03, $0b, $0b, $03, $03	; grn, pur, pur, cyn, dgry, dgry, cyn, cyn
