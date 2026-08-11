; Shared memory map — boot, locode image, and segment tooling
; Default $01=$34 (I/O out). Disk loads use $36; chip touch uses $35.

LOADER_BASE	= $0801			; disposable boot, then low BSS overlay
LOCODE_BASE	= $0900			; resident low code (locode.prg)
; future: HICODE — separate disk PRG for overflow / under-ROM code

TABLES		= $0400			; tables.asm (free bank-0 screen RAM)
SCREEN		= $4000
SCREEN_B	= $4400
BITMAP		= $6000
TEXTURES	= $4800
PISTOL_SPRITES		= $5000			; 6×64
MINIGUN_B_SPRITES	= $5180			; 3×64 chaingun frame B
MINIGUN_SPRITES		= $5240			; 6×64 chaingun A/shared
MUZZLE_FLASH_SPRITES	= $53C0			; 4×64 shared flash A/B
WPN_SPRITE_RESERVE	= $54C0			; two future weapons ($54C0–$57FF)
SQTAB1		= $5800			; Judd 2K (disk: sqt; to $5FFF)
SQTAB2		= SQTAB1 + $200
SQTAB3		= SQTAB1 + $400
SQTAB4		= SQTAB1 + $600
PAINTERS	= $8000
PAINTERS_SIZE	= $38F2			; painters.bin length (must match build)
SFX_BASE	= PAINTERS + PAINTERS_SIZE	; $B8F2 — pcsounds + pcsfreq
ENEMY_BASE	= $C000			; contiguous enemy code+gfx+SoA
ENEMY_SIZE	= $2E13			; boot stages via $8000; keep in sync with end_enemy
MAP		= $EF00			; 4K level (under-KERNAL; LoadLevel)
