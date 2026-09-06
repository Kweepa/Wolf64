; F3+W warp — paint/egfx slack (locode is full through SFX).
; Hold F3, tap W, then 1–8 / B (boss) / S (secret).
!zone warp

poll_warp
	lda $01
	pha
	lda #BANK_LOADER
	sta $01
	sei
	ldx #0					; X=1 if fired
	lda #$fe
	sta $dc00
	lda $dc01
	and #$20				; F3: 0=held
	sta tmp0
	lda #$fd
	sta $dc00
	lda $dc01
	and #$02				; W (not I)
	lsr
	eor #1					; 1=held
	ldy warp_w_prev
	sta warp_w_prev
	lda warp_armed
	bne .pw_armed
	ora warp_w_prev
	beq .pw_done				; W up
	tya
	bne .pw_done				; not rise
	lda tmp0
	bne .pw_done				; F3 up
	inc warp_armed
	jsr warp_key_scan
	sta warp_dig_prev
	jmp .pw_done
.pw_armed
	jsr warp_key_scan
	cmp warp_dig_prev
	sta warp_dig_prev
	beq .pw_done
	tay
	beq .pw_done
	sty level_num
	lda #5
	sta level_want
	stx warp_armed				; X=0
	inx
.pw_done
	lda #$7f
	sta $dc00
	cli
	pla
	sta $01
	cpx #1					; C=fired
	rts

; A = 1..8 / 9=B / 10=S if held, else 0. Caller: $01=$35, SEI.
warp_key_scan
	ldy #0
.wks_lp
	lda warp_key_col,y
	sta $dc00
	lda $dc01
	and warp_key_row,y
	beq .wks_hit
	iny
	cpy #10
	bcc .wks_lp
	lda #0
	rts
.wks_hit
	iny
	tya
	rts

warp_key_col
	!byte $7f, $7f, $fd, $fd, $fb, $fb, $f7, $f7, $f7, $fd
warp_key_row
	!byte $01, $08, $01, $08, $01, $08, $01, $08, $10, $20	; 1-8, B, S
