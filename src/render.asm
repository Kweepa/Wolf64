; Column dispatch — compiled height painters (TechDesignDoc §4)
; All heights (1..75): X = texx*16+id, Y = column. Set once here and never
; touched again by any painter — no runtime texture-id patch anywhere.
!zone render

SKY_COLOR	= $bb
FLOOR_COLOR	= $cc

; One-time boot init: TEX_HI is not disk-loaded (only TEX_LO is). Every byte
; of TEX_HI is just its TEX_LO counterpart shifted into the high nibble, so
; build it here instead of shipping/loading a second 4 KB blob.
init_tex_hi
	lda #<TEX_LO
	sta tmp0
	lda #>TEX_LO
	sta tmp1
	lda #<TEX_HI
	sta tmp2
	lda #>TEX_HI
	sta tmp3
	ldx #16				; 16 pages (4096 bytes)
.page
	ldy #0
.byte
	lda (tmp0),y
	asl
	asl
	asl
	asl
	sta (tmp2),y
	iny
	bne .byte
	inc tmp1
	inc tmp3
	dex
	bne .page
	rts

; Paint one column from DDA caches (col_texid / col_half_h / col_texx)
; Uses view_row* (set_view_rows). Y = col throughout, never reloaded — even
; the sky/floor miss path below inherits it. col_texid's sign picks the path:
; $80..$ff (only $ff used, miss — tex 0 is gold locked door) vs 0..15 (hit).
paint_column
	ldy col
	lda col_texid,y
	bpl .have_tex

; Miss: sky/floor only. Single caller (falls through here), short — inlined
; instead of jmp'd to, so the common .have_tex path pays for a branch either
; way and this path no longer also pays for a jmp. Cells 2..21 only (top/
; bottom 2 rows are the static border).
	lda #SKY_COLOR
	sta (view_row2),y
	sta (view_row3),y
	sta (view_row4),y
	sta (view_row5),y
	sta (view_row6),y
	sta (view_row7),y
	sta (view_row8),y
	sta (view_row9),y
	sta (view_row10),y
	sta (view_row11),y
	lda #FLOOR_COLOR
	sta (view_row12),y
	sta (view_row13),y
	sta (view_row14),y
	sta (view_row15),y
	sta (view_row16),y
	sta (view_row17),y
	sta (view_row18),y
	sta (view_row19),y
	sta (view_row20),y
	sta (view_row21),y
	rts

.have_tex
	ora col_texx,y				; texx already pre-shifted into the high nibble (dda.asm/doors.asm)
	tax

	lda col_half_h,y
	bne +
	lda #1
+
	cmp #MAX_HALF_H + 1
	bcc +
	lda #MAX_HALF_H
+
	sta half_h
	asl					; *2 — painter_tbl (painters.asm) is .word/page-aligned,
	sta .pj+1				; so only the operand's low byte ever needs patching
.pj	jmp (painter_tbl)
