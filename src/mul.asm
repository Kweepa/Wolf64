; Judd / Arndt a²−b² multiply — 2K square tables at SQTAB (disk: sqt)
!zone mul

; Boot LOADs sqt at MAP ($C000). install_sqtabs copies to live $D000 ($01=$34)
; before LoadLevel. init_sqtabs only patches ZP hi pointers.
; From https://6502.org/source/integers/fastmult.htm (Martin Arndt / Stephen Judd)
install_sqtabs
	lda #BANK_RAM
	sta $01
	lda #<MAP
	sta aux_l
	lda #>MAP
	sta aux_h
	lda #<SQTAB1
	sta tmp0
	lda #>SQTAB1
	sta tmp1
	ldx #8				; 8 pages = 2048
.isq_page
	ldy #0
.isq_byte
	lda (aux_l),y
	sta (tmp0),y
	iny
	bne .isq_byte
	inc aux_h
	inc tmp1
	dex
	bne .isq_page
	; fall through
init_sqtabs
	lda #>SQTAB1
	sta sq1_h
	lda #>SQTAB2
	sta sq2_h
	lda #>SQTAB3
	sta sq3_h
	lda #>SQTAB4
	sta sq4_h
	rts

; Unsigned 8×8 → 16. Y = factor1, A = factor2 → X=lo A=hi
mul_8x8
	sta sq1_l
	sta sq2_l
	eor #$ff
	sta sq3_l
	sta sq4_l
	sec
	lda (sq1_l),y
	sbc (sq3_l),y
	tax
	lda (sq2_l),y
	sbc (sq4_l),y
	rts

; The Keep API: aux * A → A=lo X=hi (middle 16 of 24-bit product)
mul_16x8
	sta sq1_l
	sta sq2_l
	eor #$ff
	sta sq3_l
	sta sq4_l
	ldy aux_l
	sec
	lda (sq1_l),y
	sbc (sq3_l),y
	lda (sq2_l),y
	sbc (sq4_l),y
	ldy aux_h
	beq .hi0
	sta tmp1
	sec
	lda (sq1_l),y
	sbc (sq3_l),y
	sta tmp2
	lda (sq2_l),y
	sbc (sq4_l),y
	sta tmp3
	clc
	lda tmp1
	adc tmp2
	tay
	lda tmp3
	adc #0
	tax
	tya
	rts
.hi0
	ldx #0
	rts

; mid(ddx * A) → sdx
calc_sdx
	sta sq1_l
	sta sq2_l
	eor #$ff
	sta sq3_l
	sta sq4_l
	ldy ddx_l
	sec
	lda (sq1_l),y
	sbc (sq3_l),y
	lda (sq2_l),y
	sbc (sq4_l),y
	sta tmp1
	ldy ddx_h
	sec
	lda (sq1_l),y
	sbc (sq3_l),y
	tax
	lda (sq2_l),y
	sbc (sq4_l),y
	sta sdx_h
	txa
	clc
	adc tmp1
	sta sdx_l
	bcc +
	inc sdx_h
+
	rts

; mid(ddy * A) → sdy
calc_sdy
	sta sq1_l
	sta sq2_l
	eor #$ff
	sta sq3_l
	sta sq4_l
	ldy ddy_l
	sec
	lda (sq1_l),y
	sbc (sq3_l),y
	lda (sq2_l),y
	sbc (sq4_l),y
	sta tmp1
	ldy ddy_h
	sec
	lda (sq1_l),y
	sbc (sq3_l),y
	tax
	lda (sq2_l),y
	sbc (sq4_l),y
	sta sdy_h
	txa
	clc
	adc tmp1
	sta sdy_l
	bcc +
	inc sdy_h
+
	rts
