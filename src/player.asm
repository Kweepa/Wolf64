; WASD only (no joystick — floating CIA bits cause phantom input)
!zone player

TURN_SPEED = 4
WALL_MARGIN = $40				; 1/4 tile keep-out from solid faces
WALL_MARGIN_HI = $100 - WALL_MARGIN	; $C0 — max frac when east/south neighbor solid
T_PLAYER	= 48				; +0..3 = N,E,S,W

; Map tiles 48..51 → player tile + facing (0=E,64=N,128=W,192=S)
find_spawn
	lda #<MAP
	sta tmp0
	lda #>MAP
	sta tmp1
	lda #0
	sta tmp2				; x
	sta tmp3				; y
.fs_loop
	ldy #0
	lda (tmp0),y
	cmp #T_PLAYER
	bcc .fs_next
	cmp #T_PLAYER + 4
	bcs .fs_next
	sec
	sbc #T_PLAYER
	tax
	lda .spawn_ang,x
	sta playera
	lda tmp2
	sta playerx_h
	lda tmp3
	sta playery_h
	lda #$80
	sta playerx_l
	sta playery_l
	rts
.fs_next
	inc tmp0
	bne +
	inc tmp1
+
	inc tmp2
	lda tmp2
	cmp #64
	bne .fs_loop
	lda #0
	sta tmp2
	inc tmp3
	lda tmp3
	cmp #64
	bne .fs_loop
	; no marker: center-ish facing east
	lda #32
	sta playerx_h
	sta playery_h
	lda #$80
	sta playerx_l
	sta playery_l
	lda #0
	sta playera
	rts

.spawn_ang
	!byte 64				; N
	!byte 0					; E
	!byte 192				; S
	!byte 128				; W


; key_bits: 0=fwd 1=back 2=turn L 3=turn R
read_keys
	lda #0
	sta key_bits

	; SquareDoom warmstart DDR — if PB is outputs, $dc01 never sees the matrix
	lda #$ff
	sta $dc02				; PA outputs (column select)
	lda #0
	sta $dc03				; PB inputs (row read)

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
	bne .push
	lda tmp2
	sta playery_l
	lda tmp3
	sta playery_h
.push
	jmp push_walls

; Keep frac ≥ WALL_MARGIN from each adjacent solid face (SquareDoom push_walls).
; tmp4/5 = player tile (probe_solid clobbers tmp0/1).
push_walls
	lda playerx_h
	sta tmp4
	lda playery_h
	sta tmp5

	; West: mapx-1
	lda tmp4
	sec
	sbc #1
	sta mapx
	lda tmp5
	sta mapy
	jsr probe_solid
	beq .pw_east
	lda playerx_l
	cmp #WALL_MARGIN
	bcs .pw_east
	lda #WALL_MARGIN
	sta playerx_l

.pw_east
	lda tmp4
	clc
	adc #1
	sta mapx
	lda tmp5
	sta mapy
	jsr probe_solid
	beq .pw_north
	lda playerx_l
	cmp #WALL_MARGIN_HI + 1		; > $C0 → snap (exact $C0 ok)
	bcc .pw_north
	lda #WALL_MARGIN_HI
	sta playerx_l

.pw_north
	; mapy-1 (north; Y grows south)
	lda tmp4
	sta mapx
	lda tmp5
	sec
	sbc #1
	sta mapy
	jsr probe_solid
	beq .pw_south
	lda playery_l
	cmp #WALL_MARGIN
	bcs .pw_south
	lda #WALL_MARGIN
	sta playery_l

.pw_south
	lda tmp4
	sta mapx
	lda tmp5
	clc
	adc #1
	sta mapy
	jsr probe_solid
	beq .pw_done
	lda playery_l
	cmp #WALL_MARGIN_HI + 1		; > $C0 → snap (exact $C0 ok)
	bcc .pw_done
	lda #WALL_MARGIN_HI
	sta playery_l
.pw_done
	rts

probe_solid
	lda mapx
	sta tmp0
	lda mapy
	sta tmp1
	jsr map_to_tile
	ldy #0
	lda (tile_l),y
	cmp #16				; solid < 16; floor/open >= 16
	bcc .solid
	lda #0
	rts
.solid
	lda #1
	rts
