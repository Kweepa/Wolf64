; Wolf64 zero page
!zone zeropage

tmp0	= $02
tmp1	= $03
tmp2	= $04
tmp3	= $05

aux_l	= $10
aux_h	= $11
mac_l	= $12
mac_h	= $13

ddx_l	= $14
ddx_h	= $15
ddy_l	= $16
ddy_h	= $17
xstep	= $18			; signed 8-bit ±1
ystep	= $19
sdx_l	= $1a
sdx_h	= $1b
sdy_l	= $1c
sdy_h	= $1d

playerx_l	= $20
playerx_h	= $21		; map X in 8.8 (high = tile)
playery_l	= $22
playery_h	= $23
playera		= $24		; angle 0..255

fracx		= $25
fracx_inv	= $26
fracy		= $27
fracy_inv	= $28
mapx		= $29
mapy		= $2a
plr_mapx	= $2b
plr_mapy	= $2c

tile_l		= $2d
tile_h		= $2e

col		= $2f
angle		= $30
dxindex		= $31
dyindex		= $32
tex_id		= $33
tex_x		= $34
side		= $35		; 0=x-hit 1=y-hit
wallz_l		= $36
wallz_h		= $37
half_h		= $38		; wall half-height in char-rows (1..12)
tex_step_l	= $39
tex_step_h	= $3a
tex_y_l		= $3b
tex_y_h		= $3c

tex_ptr_l	= $3d		; column stripe base
tex_ptr_h	= $3e

col_ptr_l	= $3f
col_ptr_h	= $40

move_dx_l	= $41
move_dx_h	= $42
move_dy_l	= $43
move_dy_h	= $44

key_bits	= $45
