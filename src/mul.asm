; Judd / Arndt a²−b² multiply — 2K square tables at SQTAB (disk: sqt)
!zone mul

; Tables are prebuilt (tools/gen_sqtab.py) and LOADed @ $5800.
; KERNAL LOAD clobbers ZP — restore hi pointers after all disk loads.
; From https://6502.org/source/integers/fastmult.htm (Martin Arndt / Stephen Judd)
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
	sta tmp1
	ldy aux_h
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
