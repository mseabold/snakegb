; vim: set syntax=asm_wlagb:
;
; Copyright (C) 2021 Matt Seabold

.define INTR_VBLANK (1 << 0)
.define INTR_STAT   (1 << 1)
.define INTR_TIMER  (1 << 2)
.define INTR_SERIAL (1 << 3)
.define INTR_JOYPAD (1 << 4)

.define INTR_VEC_VBLANK $40
.define INTR_VEC_STAT   $48
.define INTR_VEC_TIMER  $50
.define INTR_VEC_SERIAL $58
.define INTR_VEC_JOYPAD $60

.define VRAM  $8000
.define WRAM  $C000
.define OAM   $fe00
.define HIRAM $ff80

.define TILEMAP0 $9800
.define TILEMAP1 $9c00

.define VRAM_LEN  $2000
.define WRAM_LEN  $2000
.define OAM_LEN   $a0
.define HIRAM_LEN $7f

.define P1    $ff00
.define SB    $ff01
.define SC    $ff02
.define DIV   $ff04
.define TIMA  $ff05
.define TMA   $ff06
.define TAC   $ff07
.define IF    $ff0f
.define NR10  $ff10
.define NR11  $ff11
.define NR12  $ff12
.define NR13  $ff13
.define NR14  $ff14
.define NR21  $ff16
.define NR22  $ff17
.define NR23  $ff18
.define NR24  $ff19
.define NR30  $ff1a
.define NR31  $ff1b
.define NR32  $ff1c
.define NR33  $ff1d
.define NR34  $ff1e
.define NR41  $ff20
.define NR42  $ff21
.define NR43  $ff22
.define NR44  $ff23
.define NR50  $ff24
.define NR51  $ff25
.define NR52  $ff26
.define LCDC  $ff40
.define STAT  $ff41
.define SCY   $ff42
.define SCX   $ff43
.define LY    $ff44
.define LYC   $ff45
.define DMA   $ff46
.define BGP   $ff47
.define OBP0  $ff48
.define OBP1  $ff49
.define WY    $ff4a
.define WX    $ff4b
.define IE    $ffff

.memorymap
    defaultslot 1
    slot 0 $0000 $4000
    slot 1 $4000 $4000
    slot 2 $c000 $2000
    slot 3 $a000 $2000
    slot 4 $ff80 $007f
.endme


