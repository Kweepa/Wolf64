; Automap helpers that must run outside the I/O window ($D000–$DFFF).
; Linked at QS_GS_END and shipped at the end of the itm PRG.
!zone mapio

; $C800 → MAPCODE, MAPCODE_PAGES pages. Leaves $01=$34.
copy_mapcode
	lda #BANK_RAM
	sta $01
	lda #<MAPCODE_STASH
	sta aux_l
	lda #>MAPCODE_STASH
	sta aux_h
	lda #<MAPCODE
	sta tmp0
	lda #>MAPCODE
	sta tmp1
	ldx #MAPCODE_PAGES
	ldy #0
.cm_pg
	lda (aux_l),y
	sta (tmp0),y
	iny
	bne .cm_pg
	inc aux_h
	inc tmp1
	dex
	bne .cm_pg
	rts

; Y = $dc00 column. A = $dc01. Parks the matrix. $01=$34 on return.
map_cia_read
	lda #BANK_LOADER
	sta $01
	sei
	sty $dc00
	lda $dc01
	sta tmp2
	lda #$7f
	ldx joy_en
	beq +
	lda #$9f
+
	sta $dc00
	lda #BANK_RAM
	sta $01
	cli
	lda tmp2
	rts

; One frame (two raster-MSB edges). $01=$34 on return.
map_wait_frame
	lda #BANK_LOADER
	sta $01
	jsr .mw_half
	jsr .mw_half
	lda #BANK_RAM
	sta $01
	rts
.mw_half
	lda $d011
	and #$80
	sta tmp2
.mw_w
	lda $d011
	and #$80
	cmp tmp2
	beq .mw_w
	rts

; From the input IRQ. Map open: drop the return and park at irq_done.
map_irq_gate
	lda map_open
	beq .ig_no
	pla
	pla
	jmp irq_done
.ig_no
	rts
