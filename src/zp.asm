; Zero page — Wolf64 walker
!zone zp

tmp0	= $02
tmp1	= $03
tmp2	= $04
tmp3	= $05
aux_l	= $06
aux_h	= $07

; Judd square-table ZP pointers (lo patched per multiply)
sq1_l	= $08
sq1_h	= $09
sq2_l	= $0a
sq2_h	= $0b
sq3_l	= $0c
sq3_h	= $0d
sq4_l	= $0e
sq4_h	= $0f

ddx_l	= $10
ddx_h	= $11
ddy_l	= $12
ddy_h	= $13
sdx_l	= $14
sdx_h	= $15
sdy_l	= $16
sdy_h	= $17
xstep	= $18			; ±1
ystep	= $19			; unused (tile y uses ±64 via SMC)
tile_l	= $1a
tile_h	= $1b
mapx	= $1c
mapy	= $1d
plr_mapx	= $1e			; player cell cached for per-column DDA reset
plr_mapy	= $1f

playerx_l	= $20
playerx_h	= $21
playery_l	= $22
playery_h	= $23
playera		= $24		; 0..255 angle
fracx		= $25
fracx_inv	= $26
fracy		= $27
fracy_inv	= $28

col		= $29
angle		= $2a
dxindex		= $2b
dyindex		= $2c
tex_id		= $2d
texx		= $2e
wallz_l		= $2f
wallz_h		= $30
texy_l		= $31
texy_h		= $32
texstep_l	= $33
texstep_h	= $34
half_h		= $35		; 1..50 half-tiles (TDD)
side		= $36		; 0=x-hit, 1=y-hit

col_base_l	= $37
col_base_h	= $38
tex_ptr_l	= $39
tex_ptr_h	= $3a
wall_top_ht	= $3b		; clipped wall top in half-tiles
wall_end_ht	= $3c		; clipped wall end (exclusive)

move_dx_l	= $3d
move_dx_h	= $3e
move_dy_l	= $40
move_dy_h	= $41
key_bits	= $42
