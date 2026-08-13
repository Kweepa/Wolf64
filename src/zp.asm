; Zero page — Wolf64 walker
!zone zp

tmp0	= $02
tmp1	= $03
tmp2	= $04
tmp3	= $05
aux_l	= $06
aux_h	= $07
tmp4	= $3a
tmp5	= $3b

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
ystep	= $19			; ±1 Y ray step (tile stride ±64 via SMC)
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
half_h		= $31		; 1..75 half-tiles (TDD)
side		= $32		; 0=x-hit, 1=y-hit
view_back	= $33		; 0 = paint SCREEN; 1 = paint SCREEN_B
scr_front_l	= $34		; visible matrix base (HUD) — must be contiguous word
scr_front_h	= $35
tex_ptr_l	= $36
tex_ptr_h	= $37
smc_last_page	= $38		; last patched texture page
smc_last_h	= $39		; last patched half_h

move_dx_l	= $3d
move_dx_h	= $3e
move_dy_l	= $40
move_dy_h	= $41

; SquareDoom-style hold-ms input (CIA1 Timer A IRQ → read_input)
in_fwd		= $3c
in_back		= $3f
in_turn_l	= $42
in_turn_r	= $43
vel_ms		= $4e
dt_ms		= $4f				; last frame ≈ binary-ms (1..255)
; turn_acc_l/h in BSS (wolf64.asm) — fractional angle remainder

; SquareDoom-style CIA profiler (Timer A snap)
prof_snap_l	= $44
prof_snap_h	= $45
prof_now_l	= $46
prof_now_h	= $47
prof_dt_l	= $48
prof_dt_h	= $49
pp_tmp_l	= $4a
pp_tmp_h	= $4b
pp_dig_h	= $4c
pp_dig_t	= $4d

; Back-buffer row bases: view_rowN → screen + 40 + N*40 (Y = column)
view_row0	= $50
view_row1	= $52
view_row2	= $54
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

; Enemy column paint pointer (must be ZP for (ind),y)
e_col_l		= $80
e_col_h		= $81
; enemy_atan2: 2*|min| scratch for dominance test
e_abs2_l	= $82
e_abs2_h	= $83

; Weapons (HUD sprites) — keep below $90 (KERNAL disk I/O band)
key_fire		= $84		; 1 = SPACE held
spr_en			= $85		; mirror of $d015 (write-only)
fire_rpt_l		= $86
fire_rpt_h		= $87
muzzle_ms_l		= $88
muzzle_ms_h		= $89
wpn_fire_ms_l		= $8a
wpn_fire_ms_h		= $8b
cur_weapon		= $8c		; 0=knife 1=pistol 2=mg 3=chaingun
owned_weapons		= $8d		; bit0 knife .. bit3 chaingun
wpn_visible		= $8e
mg_frame		= $8f		; chaingun flash A/B

; $90–$A4 reserved for KERNAL LOAD / IEC (STATUS, STPFLG, MSGFLG,
; DFLTN/DFLTO, serial bit counters, …). Do not allocate game ZP here —
; in-play LOAD then needs no sticky-flag restores.

; Game ZP above the KERNAL disk band. LOAD clobbers some of these;
; restart_level re-inits via input_irq_init / play_sound_init / frame code.
; Skip $AE–$AF (EAL) and $B7–$BC (FNLEN/LA/SA/FA/FNADR).
wpn_pose		= $a5		; 0 idle 1 fire 2 recoil
in_fire			= $a6		; IRQ OR-latch
in_wpn_knife		= $a7
in_wpn_pistol		= $a8
in_wpn_mg		= $a9
in_wpn_chaingun		= $aa
in_strafel		= $ab		; A held (strafe left)
in_strafer		= $ac		; D held (strafe right)
random8			= $ad		; GetRandom8 state (Deathchase LCG)
e_hitscan		= $b0		; 1 = write col_enemy while painting
dt8			= $b1		; dt_ms/8 for enemy state timers
sound_index		= $b2		; $ff = idle
sound_ptr_l		= $b3
sound_ptr_h		= $b4
key_wpn_knife		= $b5
key_wpn_pistol		= $b6
key_wpn_mg		= $bd
key_wpn_chaingun	= $be
item_perp_l		= $bf		; item draw: true forward perp (wallz units)
item_perp_h		= $c0
; SFX step state — ZP so MENU overlay can share playsound (boot still owns BSS)
sound_priority		= $c1
sound_count		= $c2
sound_max		= $c3
ps_save_x		= $c4
ps_save_y		= $c5
