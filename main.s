; vim: set syntax=asm_wlagb:
.include "hardware.inc"
.include "gb_header.inc"

.define NFRAMES_HARD 5
.define NFRAMES_MEDIUM 10
.define NFRAMES_EASY 15

; Direction is store in 2 bits. Opposite directions are the complement of each other:
;    Up    - 0b00
;    Left  - 0b10
;    Right - 0b01
;    Down  - 0b11
.define DIR_UP    $00
.define DIR_LEFT  $01
.define DIR_RIGHT $02
.define DIR_DOWN  $03

.define SNAKE_START $88;Row 1 Col 1
.define SNAKE_START_TAIL $83;Row 1 Col 1
.define SNAKE_START_ATTR $86
.define SNAKE_START_DIR DIR_RIGHT
.define SNAKE_START_OFFSET $0001
.define SNAKE_START_LEN 5
.defiNE SNAKE_GROWTH 2

.define LFSR_POLY $a6

.ramsection "Work Vars" slot 2
snake_head dw
snake_tail dw
snake_growth_cnt db
dir db
framecount db
vblank_flag db
stale_flag db
joypad_pressed db
joypad_held db
xpos db
ypos db
xpos_old db
ypos_old db
vx db
vy db
lfsr db
food_tile dw
food_hit_flag db
difficulty db
speed db
.ends

.ramsection "Tile Attrs" slot 2
; Attributes per tile:
; bit 7 - Wall/Snake collision
; bit 6 - Food tile
; bit 5-4 - Reserved
; bit 3-2 - Prev snake tile
; bit 1-0 - Next snake tile
;
; Note that Prev Snake Tile is always valid, even on the snake tail. This allows the graphics routine to determine
; the last snake tile that is now stale to be updated back to an empty tile.
;
; The Next Snake Tile field for the Snake Head is unused
;
; Attributes are arranged in a 32x20 grid. 32 width is used so that attributes can map directly to
; VRAM tilemap indices. 20 Height is used as the screen is 18 tiles + 2 rows for upper and lower collisions
tile_attributes ds 640
.ends

.bank 0 slot 0
.org INTR_VEC_VBLANK
    jp vblank_isr

.org $100
    nop
    jp $150

.org $150
main:
    call wait_vblank

    xor A
    ld (LCDC),A ; disable LCD

    ld HL,$fe00
    ld BC,$a0
    call memset

    ; Load tile set into VRAM
    ld HL,$8000
    ld DE,tiles
    ld BC,$0210
    call memcpy

    ; Keep HL at the same location
    ld DE,font
    ld BC,SIZEOF_FONT

-   ld A,B
    or C
    jr z,+
    ld A,(DE)
    inc DE
    ld (HL+),A
    ld (HL+),A
    dec BC
    jr -

+   ld HL,TILEMAP0
    ld DE,start_screen_map
    ld C,18
-   ld B,20
--  ld A,(DE)
    ld (HL+),A
    inc DE
    dec B
    jr nz,--
    xor A
    ld B,12
--- ld (HL+),A
    dec B
    jr nz,---
    dec C
    jr nz,-

    xor A
    ld (joypad_held),A
    ld (joypad_pressed),A
    ld (difficulty),A

    ld HL,$fe00
    ld (HL),96
    inc HL
    ld (HL),56
    inc HL
    ld (HL),2

    ld A,$93
    ld (LCDC),A ; Restart the LCD (8000 data made, BG map at 9800)


-   call wait_vblank
    call get_joypad

    ld A,(joypad_pressed)
    ld B,A
    ld A,(difficulty)
    bit 0,B
    jr z,+
    ld A,(DIV)
    ld (lfsr),A
    jp reset_game
+   bit 7,B
    jr z,+
    cp A,2
    jr z,-
    inc A
    ld (difficulty),A
    ld A,($fe00)
    add 16
    ld ($fe00),A
    jr -
+   bit 6,B
    jr z,-
    or A
    jr z,-
    dec A
    ld (difficulty),A
    ld A,($fe00)
    add -16
    ld ($fe00),A
    jr -

reset_game:
    call wait_vblank

    xor A
    ld (LCDC),A ; disable LCD

    ; Set tilemap to all 0
    LD HL,TILEMAP0
    ld BC,$400
    call memset

    ; Set up tile attributes
    ;
    ; One line of wall at top of board
    ld HL,tile_attributes
    ld DE,nonplayable_line
    ld BC,$20
    call memcpy

    ; 18 lines of playable space
    ld B,18

--- push BC
    ld BC,$20
    ld DE,playable_line
    call memcpy
    pop BC
    dec B
    jr nz,---

    ; Final lower wall line
    ld DE,nonplayable_line
    ld BC,$20
    call memcpy

    ld HL,difficulty_map
    ld B,0
    ld A,(difficulty)
    ld C,A
    add HL,BC
    ld A,(HL)
    ld (speed),A

    ; Initialize the frame counter that control movement speed
    ld A,(speed)
    ld HL,framecount
    ld (HL),A

    ; Set up snake start position
    ld C,SNAKE_START_DIR << 1
    ld B,0
    ld HL,dir_offset_map
    add HL,BC
    ld C,(HL)
    inc HL
    ld B,(HL)

    ld D,>SNAKE_START
    ld E,<SNAKE_START

    ld HL,snake_tail
    ld (HL),E
    inc HL
    ld (HL),D

    ld A,SNAKE_START_LEN
-   push AF
    ld A,$80 | ((SNAKE_START_DIR << 2) ~ $0c) | SNAKE_START_DIR
    ld HL,tile_attributes
    add HL,DE
    ld (HL),A

    ld A,$01
    ld HL,TILEMAP0
    add HL,DE
    ld (HL),A

    pop AF
    dec A
    jr z,+

    ld H,D
    ld L,E
    add HL,BC
    ld D,H
    ld E,L
    jr -

+   ld HL,snake_head
    ld (HL),E
    inc HL
    ld (HL),D

    ; Set joypad variables to 0
    xor A
    ld HL,joypad_pressed
    ld (HL),A
    inc HL
    ld (HL),A
    ld (stale_flag),A
    ld (food_hit_flag),A
    ld (snake_growth_cnt),A

-   call rand_tile_offset
    ld HL,tile_attributes
    add HL,BC
    bit 7,(HL)
    jr nz,-

    ld HL,food_tile
    ld (HL),C
    inc HL
    ld (HL),B
    ld HL,tile_attributes
    add HL,BC
    ld A,$40
    ld (HL),A

    ld A,$01
    ld (IE),A

    ld A,SNAKE_START_DIR
    ld HL,dir
    ld (HL),A

    ld A,$e4
    ld (BGP),A

    ;Scroll 1 tile right and down (hide the invisible edge walls
    ld A,8
    ld (SCX),A
    ld (SCY),A

    ld A,$91
    ld (LCDC),A ; Restart the LCD (8000 data made, BG map at 9800)
    ei
    nop

main_loop:
    halt
    nop
    ld A,$01
    ld HL,vblank_flag
    cp (HL)
    jr NZ,main_loop

    xor A
    ld (HL),A

    ld HL,framecount
    dec (HL)
    jr nz,main_loop

    ld A,(speed)
    ld (HL),A

    ld HL,dir
    ld B,0
    ld C,(HL)
    sla C
    ld HL,dir_offset_map
    add HL,BC
    ld C,(HL)
    inc HL
    ld B,(HL)
    push BC

    ld HL,snake_head
    ld E,(HL)
    inc HL
    ld D,(HL)

    ld HL,tile_attributes

    add HL,DE ; Add the head tile's offset
    push HL ; Stash the head tile's attribute address
    add HL,BC ; Add an offset based on current direction (destination tile)
    ld A,(HL) ; Get the destination tile's attributes

    ; If the tile is a wall, just skip to the next movement frame without moving
    bit 7,A
    jr z,+
    pop HL
    pop BC
    jp reset_game

    ; Get direction again
+   ld DE,dir
    ld A,(DE)
    ld D,A


    ; First check if the new head hit the food tile
    ld A,(HL)
    bit 6,A
    jr z,+
    ld A,1
    ld (food_hit_flag),A
    ld A,SNAKE_GROWTH+1
    ld (snake_growth_cnt),A

    ; Set up new tiles attributes
+   ld A,$80
    ld E,D
    sla E
    sla E ; C = dir << 2
    or E ; Mask on the dir bits
    xor $0c ; Complement the dir (previous tile is in the reverse direction)

    ld (HL),A ; Store the new attributes

    pop HL ; Retrieve the head tile's address from the stack
    ld A,(HL)
    and $fc
    or D
    ld (HL),A

    ; Finally, update head and tail
    pop BC ; dir offset
    ld HL,snake_head
    ld A,(HL)
    add C
    ld (HL+),A
    ld A,(HL)
    adc B
    ld (HL),A


    xor A
    ld HL,snake_growth_cnt
    or (HL)
    jr z,+
    dec (HL)
    jr nz,++

+   ld HL,snake_tail
    push HL
    ld E,(HL)
    inc HL
    ld D,(HL)

    ld HL,tile_attributes
    add HL,DE
    ld A,(HL)
    res 7,A
    ld (HL),A
    and $03
    sla A

    ld C,A
    ld B,0

    ld HL,dir_offset_map
    add HL,BC
    ld C,(HL)
    inc HL
    ld B,(HL)

    ld A,E
    add C
    ld E,A
    ld A,D
    adc B
    ld D,A

    pop HL
    ld (HL),E
    inc HL
    ld (HL),D

++  ld HL,stale_flag
    ld A,$01
    ld (HL),A

    ld A,(food_hit_flag)
    or A
    jr z,+

-   call rand_tile_offset
    ld HL,tile_attributes
    add HL,BC
    ld A,(HL)
    bit 7,A
    jr nz,-

    or $40
    ld (HL),A

    ld HL,food_tile
    ld (HL),C
    inc HL
    ld (HL),B

    xor A
    ld (food_hit_flag),A

+   jp main_loop

; A - new map value
; B - X pos
; C - Y pos
set_map_pos:
    push AF
    push DE
    push HL

    ld D,$00
    ld E,B

    push DE

    ld E,C

    ld HL,TILEMAP0

    ;; Multiply DE by 32
    sla E
    rl D
    sla E
    rl D
    sla E
    rl D
    sla E
    rl D
    sla E
    rl D

    add HL,DE

    pop DE
    add HL,DE

    ld (HL),A

    pop HL
    pop DE
    pop AF
    ret

get_joypad:
    ld HL,$ff00
    ld A,$20
    ld (HL),A
    ld A,(HL)
    ld A,(HL)
    ld A,(HL)
    ld A,(HL)
    cpl
    and $0f
    swap A
    ld B,A
    ld A,$10
    ld (HL),A
    ld A,(HL)
    ld A,(HL)
    ld A,(HL)
    ld A,(HL)
    cpl
    and $0f
    or B
    ld B,A
    ld HL,joypad_held ;TODO faster if this is in HRAM
    ld A,(HL)
    cpl
    and B
    ld (HL),B
    ld HL,joypad_pressed
    ld (HL),A
    ret

check_pressed:
    ld HL,joypad_pressed
    ld A,(HL)

    ; Nothing to do if nothing was pressed
    or A
    ret z

    ld HL,dir

    bit 7,A
    jr z,@joypad_check_up
    ld B,DIR_DOWN
    jp +
@joypad_check_up:
    bit 6,A
    jr z,@joypad_check_left
    ld B,DIR_UP
    jp +
@joypad_check_left:
    bit 5,A
    jr z,@joypad_check_right
    ld B,DIR_LEFT
    jp +
@joypad_check_right:
    bit 4,A
    ret z
    ld B,DIR_RIGHT

+   ld A,B
    xor (HL)
    cp 3 ; Can't move in opposite direction (insta-death
    ret z
    ld (HL),B
    ret

; HL - destination
; DE - source
; BC - length
memcpy:
-   ld A,B
    or C
    ret z
    ld A,(DE)
    ld (HL+),A
    inc DE
    dec BC
    jr -

memset:
-   ld D,A
    ld A,B
    or C
    ret z
    ld A,D
    ld (HL+),A
    dec BC
    jr -

vblank_isr:
    push AF
    push BC
    push DE
    push HL

    ld HL,stale_flag
    ld A,(HL)
    or A
    jr z,@joypad

    ld HL,snake_tail
    ld C,(HL)
    inc HL
    ld B,(HL)

    ld HL,tile_attributes
    add HL,BC
    ld A,(HL)

    and $0c
    sra A

    ld E,A
    ld D,0
    ld HL,dir_offset_map
    add HL,DE
    ld E,(HL)
    inc HL
    ld D,(HL)

    ld HL,TILEMAP0
    add HL,DE
    add HL,BC
    xor A
    ld (HL),A

    ld HL,snake_head
    ld E,(HL)
    inc HL
    ld D,(HL)

    ld HL, TILEMAP0
    add HL,DE
    ld A,$01
    ld (HL),A

    ld HL,food_tile
    ld C,(HL)
    inc HL
    ld B,(HL)
    ld HL,TILEMAP0
    add HL,BC
    ld A,$02
    ld (HL),A

    xor A
    ld HL,stale_flag
    ld (HL),A

@joypad:
    push AF
    call get_joypad
    pop AF

    call check_pressed

    ld HL,vblank_flag
    ld A,$01
    ld (HL),A

    pop HL
    pop DE
    pop BC
    pop AF
    reti

prng_rand:
    ld HL,lfsr
    ld A,(HL)
    rrca
    jr nc,+
    xor LFSR_POLY
+   ld (HL),A
    ret

rand_tile_offset:
    ld B,0
    call prng_rand
    and $1f
    ld E,A
    ld D,0
    ld HL,rand_18_table
    add HL,DE
    ld C,(HL)

    ;; << 5 (*32)
    sla C
    rl B
    sla C
    rl B
    sla C
    rl B
    sla C
    rl B
    sla C
    rl B

    call prng_rand
    and $1f
    ld E,A
    ld D,0
    ld HL,rand_20_table
    add HL,DE
    ld A,(HL)
    or C
    ld C,A

    ret

wait_vblank:
    push AF
    push BC

    ld B,$03
    ld C,$01

-   ld A,(STAT)
    and B
    cp C
    jr nz,-

    pop BC
    pop AF

    ret

.bank 1 slot 1
.org $00

nonplayable_line:
    .db $80, $80, $80, $80, $80, $80, $80, $80
    .db $80, $80, $80, $80, $80, $80, $80, $80
    .db $80, $80, $80, $80, $80, $80, $80, $80
    .db $80, $80, $80, $80, $80, $80, $80, $80

playable_line:
    .db $80, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $80, $80, $80
    .db $80, $80, $80, $80, $80, $80, $80, $80

dir_offset_map:
    .db $e0, $ff, $ff, $ff, $01, $00, $20, $00

difficulty_map:
    .db NFRAMES_EASY, NFRAMES_MEDIUM, NFRAMES_HARD

; This isn't perfect (uneven distribution), but it's the most
; efficient way take a LFSR-generated pseudo-random byte to X
; or Y coordinate. This uses the lower 5 bits of the PRNG
; and maps them to a scaled X or Y value.
rand_20_table:
    .db  1,  1,  2,  2,  3,  4,  4,  5
    .db  6,  6,  7,  7,  8,  9,  9, 10
    .db 11, 11, 12, 12, 13, 14, 14, 15
    .db 16, 16, 17, 17, 18, 19, 19, 20

rand_18_table:
    .db  1,  1,  2,  2,  3,  3,  4,  4
    .db  5,  6,  6,  7,  7,  8,  8,  9
    .db 10, 10, 11, 11, 12, 12, 13, 13
    .db 14, 15, 15, 16, 16, 17, 17, 18

tiles:
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $ff, $ff, $ff, $81, $ff, $bd, $ff, $bd
    .db $ff, $bd, $ff, $bd, $ff, $81, $ff, $ff
    .db $00, $00, $18, $18, $18, $18, $7e, $7e
    .db $7e, $7e, $18, $18, $18, $18, $00, $00
    .db $3f, $3f, $20, $20, $20, $20, $20, $20
    .db $20, $20, $20, $20, $20, $20, $20, $20
    .db $ff, $ff, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $f0, $f0, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $0c, $0c, $0c, $0c, $0a, $0a, $0a, $0a
    .db $09, $09, $09, $09, $08, $08, $08, $08
    .db $00, $00, $01, $01, $01, $01, $01, $01
    .db $01, $01, $01, $01, $81, $81, $81, $81
    .db $3f, $3f, $40, $40, $40, $40, $40, $40
    .db $40, $40, $40, $40, $40, $40, $40, $40
    .db $80, $80, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $20, $20, $20, $20, $20, $20, $20, $20
    .db $20, $20, $20, $20, $20, $20, $20, $20
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $03, $03, $0c, $0c, $70, $70
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $60, $60, $80, $80, $00, $00, $00, $00
    .db $20, $20, $20, $20, $20, $20, $3f, $3f
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $ff, $ff
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $f0, $f0
    .db $10, $10, $10, $10, $10, $10, $10, $10
    .db $08, $08, $08, $08, $08, $08, $08, $08
    .db $08, $08, $08, $08, $08, $08, $08, $08
    .db $41, $41, $41, $41, $21, $21, $21, $21
    .db $11, $11, $11, $11, $09, $09, $09, $09
    .db $40, $40, $40, $40, $40, $40, $7f, $7f
    .db $40, $40, $40, $40, $40, $40, $40, $40
    .db $00, $00, $00, $00, $00, $00, $80, $80
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $23, $23, $2c, $2c, $30, $30, $20, $20
    .db $20, $20, $20, $20, $20, $20, $20, $20
    .db $80, $80, $80, $80, $80, $80, $40, $40
    .db $20, $20, $20, $20, $10, $10, $08, $08
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $3f, $3f, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $ff, $ff, $00, $00, $00, $00, $00, $00
    .db $10, $10, $10, $10, $10, $10, $10, $10
    .db $f0, $f0, $00, $00, $00, $00, $00, $00
    .db $08, $08, $08, $08, $08, $08, $08, $08
    .db $08, $08, $00, $00, $00, $00, $00, $00
    .db $05, $05, $05, $05, $03, $03, $03, $03
    .db $01, $01, $01, $01, $00, $00, $00, $00
    .db $40, $40, $40, $40, $40, $40, $40, $40
    .db $40, $40, $40, $40, $3f, $3f, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $ff, $ff, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $80, $80, $00, $00
    .db $04, $04, $04, $04, $02, $02, $01, $01
    .db $01, $01, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $80, $80, $40, $40, $40, $40
    .db $20, $20, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00

start_screen_map:
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $03, $04, $05, $00, $06, $07
    .db $00, $00, $08, $04, $09, $00, $0a, $0b
    .db $0c, $00, $00, $00, $00, $00, $0d, $0e
    .db $0f, $00, $10, $11, $00, $00, $12, $0e
    .db $13, $00, $14, $15, $00, $00, $00, $00
    .db $00, $00, $16, $17, $18, $00, $19, $1a
    .db $00, $00, $1b, $1c, $1d, $00, $0a, $1e
    .db $1f, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $20, $00, $20, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $46
    .db $42, $54, $5a, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $4e
    .db $46, $45, $4a, $56, $4e, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $49
    .db $42, $53, $45, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00
    .db $00, $00, $00, $00, $00, $00, $00, $00

font:
    .incbin "font.bin" FSIZE SIZEOF_FONT
