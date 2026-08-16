; Secret pushwalls — walk into tile 14; moves one block if the cell beyond is clear.
!zone pushwall

; mapx,mapy = bumped cell
try_push_wall
	lda mapx
	sta tmp0
	lda mapy
	sta tmp1
	jsr door_tile_at
	cmp #T_PUSHWALL
	beq +
	rts
+
	; Away from player on bump axis
	lda #1
	ldx mapx
	cpx playerx_h
	beq .yd
	bcs .dir
	lda #3
	bne .dir
.yd
	lda #2
	ldx mapy
	cpx playery_h
	bcs .dir
	lda #0
.dir
	tax
	clc
	lda mapx
	adc .dx,x
	sta tmp2
	clc
	lda mapy
	adc .dy,x
	sta tmp3
	cmp #64
	bcs .no
	lda tmp2
	cmp #64
	bcs .no
	sta tmp0
	lda tmp3
	sta tmp1
	jsr door_tile_at
	cmp #18
	bcc .no

	; origin → floor
	lda mapx
	sta tmp0
	lda mapy
	sta tmp1
	jsr map_to_tile
	ldy #0
	lda #18
	sta (tile_l),y

	; dest ← pushwall
	lda tmp2
	sta tmp0
	lda tmp3
	sta tmp1
	jsr map_to_tile
	ldy #0
	lda #T_PUSHWALL
	sta (tile_l),y

	lda #SOUND_PUSHWALL
	jmp play_sound
.no
	rts

.dx	!byte 0, 1, 0, 255
.dy	!byte 255, 0, 1, 0
