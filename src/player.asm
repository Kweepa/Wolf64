; WASD only (no joystick — floating CIA bits cause phantom input)
!zone player

TURN_SPEED = 4

; key_bits: 0=fwd 1=back 2=turn L 3=turn R
read_keys
	lda #0
	sta key_bits

	lda #$ff
	sta $dc02				; PA outputs (column select)

	; W / A / S on PA1 = $FD
	lda #$fd
	sta $dc00
	lda $dc01
	tax
	and #$02				; W = forward
	bne +
	lda key_bits
	ora #%00000001
	sta key_bits
+
	txa
	and #$20				; S = back
	bne +
	lda key_bits
	ora #%00000010
	sta key_bits
+
	txa
	and #$04				; A = turn left
	bne +
	lda key_bits
	ora #%00000100
	sta key_bits
+

	; D on PA2 = $FB
	lda #$fb
	sta $dc00
	lda $dc01
	and #$04				; D = turn right
	bne +
	lda key_bits
	ora #%00001000
	sta key_bits
+
	rts

player_move
	jsr read_keys

	lda key_bits
	and #%00000100				; left → turn CCW
	beq +
	sec
	lda playera
	sbc #TURN_SPEED
	sta playera
+
	lda key_bits
	and #%00001000				; right → turn CW
	beq +
	clc
	lda playera
	adc #TURN_SPEED
	sta playera
+

	lda key_bits
	and #%00000001				; up → forward
	beq .back
	lda #0
	sta tmp0
	jsr walk
	rts
.back
	lda key_bits
	and #%00000010
	beq .done
	lda #1
	sta tmp0
	jsr walk
.done
	rts

; Walk along facing. tmp0=0 forward, 1 back.
; sintab/costab amp 64 → 8.8 frac (±64/256 ≈ 0.25 tile/frame).
walk
	ldy playera
	lda costab,y
	sta move_dx_l
	cmp #$80
	lda #0
	bcc +
	lda #$ff
+
	sta move_dx_h
	; Y grows south; negate sin so angle 64 (north) decreases Y
	lda #0
	sec
	sbc sintab,y
	sta move_dy_l
	cmp #$80
	lda #0
	bcc +
	lda #$ff
+
	sta move_dy_h

	lda tmp0
	beq .apply
	; negate (backwards)
	lda #0
	sec
	sbc move_dx_l
	sta move_dx_l
	lda #0
	sbc move_dx_h
	sta move_dx_h
	lda #0
	sec
	sbc move_dy_l
	sta move_dy_l
	lda #0
	sbc move_dy_h
	sta move_dy_h

.apply
	; X axis
	clc
	lda playerx_l
	adc move_dx_l
	sta tmp2
	lda playerx_h
	adc move_dx_h
	sta tmp3
	lda tmp3
	sta mapx
	lda playery_h
	sta mapy
	jsr probe_solid
	bne .try_y
	lda tmp2
	sta playerx_l
	lda tmp3
	sta playerx_h
.try_y
	clc
	lda playery_l
	adc move_dy_l
	sta tmp2
	lda playery_h
	adc move_dy_h
	sta tmp3
	lda playerx_h
	sta mapx
	lda tmp3
	sta mapy
	jsr probe_solid
	bne .out
	lda tmp2
	sta playery_l
	lda tmp3
	sta playery_h
.out
	rts

probe_solid
	lda mapx
	sta tmp0
	lda mapy
	sta tmp1
	jsr map_to_tile
	ldy #0
	lda (tile_l),y
	beq .clear
	cmp #16
	bcs .clear
	cmp #11				; doors open until drawn
	bcc .solid
	cmp #14
	bcc .clear
.solid
	lda #1
	rts
.clear
	lda #0
	rts
