; Assemble compiled painters to a plain binary at their run address
!cpu 6510
!to "painters.bin", plain

TEXTURES	= $4800
tmp0		= $02
tmp1		= $03
tmp2		= $04
tmp3		= $05
tmp4		= $3a
tmp5		= $3b
half_h		= $31
tex_ptr_l	= $36
tex_ptr_h	= $37
view_row0	= $50
view_row1	= $52
view_row2	= $54				; near painter dest start
view_row3	= $56
view_row4	= $58
view_row5	= $5a
view_row6	= $5c
view_row7	= $5e
view_row8	= $60
view_row9	= $62
view_row10	= $64
view_row11	= $66
view_row12	= $68
view_row13	= $6a
view_row14	= $6c
view_row15	= $6e
view_row16	= $70
view_row17	= $72
view_row18	= $74
view_row19	= $76
view_row20	= $78
view_row21	= $7a
view_row22	= $7c
view_row23	= $7e

*= $8000
!source "painters.asm"
