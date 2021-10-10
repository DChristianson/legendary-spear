    processor 6502
    include "vcs.h"
    include "macro.h"

NTSC = 0
PAL60 = 1

    IFNCONST SYSTEM
SYSTEM = NTSC
    ENDIF

; ----------------------------------
; constants

#if SYSTEM = NTSC
; NTSC Colors
SKY_BLUE = $A0
SKY_YELLOW = $FA
DARK_WATER = $A0
SUN_RED = $30
CLOUD_ORANGE = $22
GREY_SCALE = $02 
WHITE_WATER = $0A
GREEN = $B3
RED = $43
YELLOW = $1f
WHITE = $0f
BLACK = 0
BROWN = $F1
#else
; PAL Colors
; Mapped by Al_Nafuur @ AtariAge
SKY_BLUE = $92
SKY_YELLOW = $2A
DARK_WATER = $92
SUN_RED = $42
CLOUD_ORANGE = $44
GREY_SCALE = $02 
WHITE_WATER = $0A
GREEN = $72
RED = $65
YELLOW = $2E
WHITE = $0E
BLACK = 0
BROWN = $21
#endif

RIDER_HEIGHT = 24
NUM_RIDERS = 5
PLAYER_COLOR = BLACK
RIDER_ANIMATE_SPEED = 3
PLAYER_ANIMATE_SPEED = 3
PLAYER_STRIKE_COUNT = 16
PLAYER_CHARGE_TICKS = 64
RIDER_RESP_START = $b8
RIDER_GREEN_TYPE = GREEN
RIDER_ROCK_TYPE = $00
RIDER_HIT_BOX = RIDER_HEIGHT - 8
RAIL_HEIGHT = 6
LOGO_HEIGHT = 6
WINNING_SCORE = $99
RIDER_HIT_SOUND = $0a
PLAYER_HIT_SOUND = $02
GALLOP_SOUND = $00
GALLOP_PATTERN = $d8

; ----------------------------------
; variables

  SEG.U variables

    ORG $80

game_state          ds 1
game_dark           ds 1
game_award          ds 1
sound_track         ds 1
rider_animate       ds 1 ; animation timer
rider_tile          ds 5 ; rider animation tile
rider_timer         ds 5 ; rider movement timer
rider_hpos          ds 5 
rider_colors        ds 5
rider_move          ds 5
rider_speed         ds 5
rider_hit           ds 5
rider_damaged       ds 5
rider_pattern       ds 1
player_animate      ds 1
player_tile         ds 1
player_vindex       ds 1
player_vdelay       ds 1
player_vpos         ds 1
player_hpos         ds 1
player_charge       ds 1
player_charge_delay ds 1
player_fire         ds 1
player_damaged      ds 1
player_health       ds 1
player_score        ds 1
player_below_rider  ds 1
; overlapping tmp vars
tmp              ; used in rider pattern
tmp_award_color  ; used in horizon
tmp_prev_ctrl       ds 1 ; used in vblank kernels
tmp_award_inc       ds 1 ; used in horizon
tmp_addr_0          ds 2 ; used in vblank kernels
tmp_addr_1          ds 2 ; used in vblank kernels

    SEG

; ----------------------------------
; code

  SEG
    ORG $F000

Reset

    ; do the clean start macro
            CLEAN_START

  ; black playfield sidebars, on top of players
            lda #$30
            sta PF0
            lda #$05
            sta CTRLPF
            ldx #$0f
            stx game_dark

newFrame

  ; Start of vertical blank processing
            
            lda #0
            sta VBLANK
            sta COLUBK              ; background colour to black

    ; 3 scanlines of vertical sync signal to follow

            ldx #%00000010
            stx VSYNC               ; turn ON VSYNC bit 1

            sta WSYNC               ; wait a scanline
            sta WSYNC               ; another
            sta WSYNC               ; another = 3 lines total

            sta VSYNC               ; turn OFF VSYNC bit 1

    ; 37 scanlines of vertical blank to follow

;--------------------
; VBlank start

            lda #1
            sta VBLANK

            lda #42    ; vblank timer will land us ~ on scanline 34
            sta TIM64T

;---------------------
; scoring kernel
            lda player_charge
            beq scoringLoop_no_charge
            lda #0
            sta player_below_rider
scoringLoop_no_charge
            sta tmp              ; total damage
            ldx #NUM_RIDERS - 1 
            dec player_damaged
            bpl scoringLoop
            sta player_damaged   ; note is 0
scoringLoop
            lda rider_colors,x         ;4   4
            cmp #RIDER_GREEN_TYPE      ;2   6
            beq scoringLoop_end        ;2   8
            tay                        ;2  10; store if it's a rock
            lda rider_damaged,x        ;4  14
            bpl scoringLoop_decay      ;2  16
            lda rider_hit,x            ;4  20
            bpl scoringLoop_end        ;2  24 ; bit 7 not set
            ; hit scored on something
            tya                        ;
            ora player_charge          ;---- charging rock hit
            beq scoringLoop_rock_hit
scoringLoop_damage_check
            lda #$04                   ;2  26
            sec                        ;2  28
            sbc rider_speed,x          ;4  32
            ldy player_below_rider
            bmi scoringLoop_player_hit
            ldy player_fire            ;3  39
            beq scoringLoop_player_hit ;2  41
scoringLoop_rider_hit
            inc rider_move,x           ;----- rider will come back stronger
            sed                        ;2  43
            clc                        ;2  45
            adc player_score           ;2  47
            bcc scoringLoop_save_score ;2  49
            lda #WINNING_SCORE         ;2  51
scoringLoop_save_score
            sta player_score           ;3  54
            cld                        ;2  56
            lda #$08                   ;2  58
            sta rider_damaged,x        ;4  62
            lda #RIDER_HIT_SOUND       ;2  64
            sta AUDC1                  ;3  67
            jmp scoringLoop_end        ;3  70
scoringLoop_rock_hit
            lda #$04
scoringLoop_player_hit
            clc                        ;2  44
            adc tmp                    ;3  47
            sta tmp                    ;3  50
            lda #$1f                   ;3  53
            sta player_damaged         ;3  56
            sta rider_damaged,x        ;4  60
            sta rider_move,x           ; -- slow this rider down
scoringLoop_player_hit_end 
            ;ldy #$0                   ;2  62 y is 0
            sty player_charge_delay    ;3  65
            sty player_charge
            jmp scoringLoop_end  ;3  68
scoringLoop_decay
            sta AUDF1
            sta AUDV1
            lda rider_colors,x
            rol 
            dec rider_damaged,x
            bpl scoringLoop_rider_clear
            lda #RIDER_GREEN_TYPE
scoringLoop_rider_clear
            sta rider_colors,x
scoringLoop_end
            dex
            bpl scoringLoop

damageLoop_assess
            ldy tmp
            beq damageLoop_skip
            lda #PLAYER_HIT_SOUND      ;2  --
            sta AUDC1                  ;3  --
            lda player_health
damageLoop_incur
            asl
            dey 
            bne damageLoop_incur
            sta player_health
damageLoop_skip

gameAttract
            lda game_state
            bne soundTrack_start
            sta AUDV0 ; volume 0
            sta AUDV1 ; volume 0
            ldx #$28
            stx player_vpos
            stx rider_pattern
            lda #$03
            sta player_hpos
            jmp soundTrack_end

soundTrack_start
            lda player_animate
            bne soundTrack_end
            clc 
            ror sound_track
            bcc soundTrack_clear
            ldy #$02
            jmp soundTrack_update
soundTrack_clear
            bne soundTrack_lo
            lda #GALLOP_PATTERN 
            sta sound_track ; save gallop pattern
soundTrack_lo
            ;ldy #$00  - optimization y is 0
soundTrack_update
            sty AUDV0 ; y is volume
soundTrack_end


;-----------------------------
; animate player

animatePlayer
            ldy player_tile
            lda game_state           
            bne animatePlayer_start
            dec player_animate
            bpl animatePlayer_end
            lda #$0f
            cmp game_dark
            beq animatePlayer_reset
            inc game_dark
            jmp animatePlayer_reset

animatePlayer_start
            lda player_damaged
            beq animatePlayer_seq
            ldy #$03                   ; load damaged player graphics
            jmp animatePlayer_save

animatePlayer_seq
            dec player_animate
            bpl animatePlayer_end
            lda game_dark
            beq animatePlayer_go
            dec game_dark
animatePlayer_go 
            dey
            bpl animatePlayer_save
            ldy #$02
animatePlayer_save
            sty player_tile
animatePlayer_reset
            lda #PLAYER_ANIMATE_SPEED
            sta player_animate
animatePlayer_end


 ; now that we have the player tile, load it up
            clc
            lda #<RIDER_SPRITE_START
            dey
            bmi stackPlayer_load_addr
stackPlayer_tile_loop
            adc #48
            dey
            bpl stackPlayer_tile_loop
stackPlayer_load_addr
            sta tmp_addr_0
            adc #24
            sta tmp_addr_1
            lda #>RIDER_SPRITE_START
            sta tmp_addr_0+1
            sta tmp_addr_1+1

stackPlayer_start
; we're going to copy the current graphics to the stack
; to save memory this is modified to use reversed rider graphics
            lda #$00 ; kludge - we know last two entries are 0
            pha 
            pha 
            lda #$05
            sta tmp_prev_ctrl
            ldy #1
stackPlayer_loop
            lda (tmp_addr_0),y
            eor #$f0 ;invert hmp 
            clc
            adc #$10
            tax 
            and #$0f
            cmp tmp_prev_ctrl
            sta tmp_prev_ctrl
            beq stackPlayer_push_inv_ctrl
            bmi stackPlayer_step_down
stackPlayer_step_up
            txa
            sec
            sbc #$40
            pha            
            lda #$1f
            pha
            jmp stackPlayer_loop_dec 
stackPlayer_step_down
            cmp #$05
            bmi stackPlayer_step_down_0
            txa
            clc
            adc #$40
            pha
            jmp stackPlayer_push_graphics
stackPlayer_step_down_0
            txa
            sec
            sbc #$80
            pha            
            jmp stackPlayer_push_graphics
stackPlayer_push_inv_ctrl
            txa
            pha            
            and #$02 ; hack for if this is a quad
            beq stackPlayer_push_graphics
            lda #$1f
            jmp stackPlayer_push_graphics_0
stackPlayer_push_graphics
            lda (tmp_addr_1),y 
stackPlayer_push_graphics_0
            pha
stackPlayer_loop_dec
            iny
            cpy #RIDER_HEIGHT
            bmi stackPlayer_loop

            ldy #$00 ; use to sta 0's
animatePlayer_eval_fire 
            ldx player_fire
            bmi animatePlayer_eval_fire_cooldown
            bne animatePlayer_fire_active
            lda #$0f ; edit player graphic
            sta $e4
            jmp animatePlayer_fire_end
animatePlayer_fire_active
            dex 
            bne animatePlayer_fire_save
            ldx -#PLAYER_STRIKE_COUNT
            jmp animatePlayer_fire_save
animatePlayer_eval_fire_cooldown
            inx 
            bmi animatePlayer_fire_save
            stx player_charge
animatePlayer_fire_save
            stx player_fire
animatePlayer_fire_end

            lda #$80                 ;3   8
            ldx game_state           ;3   3    
            bne movePlayer           ;2   5
movePlayer_game
            bit INPT4                ;3  11
            bne movePlayer_game_start_check ;2  13
            lda game_dark
            cmp #$0f
            bne movePlayer_end_jmp
            inc player_charge_delay        ;5  20
            jmp movePlayer_end
movePlayer_game_start_check
            ldx player_charge_delay
            beq movePlayer_end_jmp
            sty player_charge_delay
            sty player_score
            ldx #$ff
            stx player_health
            inc game_state
movePlayer_end_jmp
            jmp movePlayer_end

movePlayer
            ldx player_damaged            ;3   3
            bne movePlayer_horiz_start    ;2   5
            bit INPT4                     ;3  11
            bne movePlayer_button_up      ;2  13
            ldx player_fire
            bne movePlayer_horiz_start
            ldx player_charge_delay
            cpx #PLAYER_CHARGE_TICKS
            bpl movePlayer_inc_charge
            inc player_charge_delay
            jmp movePlayer_horiz_start    
movePlayer_inc_charge
            inc player_charge             
            jmp movePlayer_horiz_start    
movePlayer_button_up
            ldx player_charge_delay       ;3  24
            beq movePlayer_horiz_start    ;2  26
            lda #PLAYER_STRIKE_COUNT      ;2  28
movePlayer_skip_charge
            sta player_fire               ;3  31
            sty player_charge_delay       ; optimize, y = 0

movePlayer_horiz_start
            ldx player_fire            ;3   3
            bne movePlayer_fire        ;2   5
            bit SWCHA                  ;3  11
            beq movePlayer_right       ;2  13
            lsr                        ;2  15
            bit SWCHA                  ;3  18
            beq movePlayer_left        ;2  20
            jmp movePlayer_vert_start  ;3  36
movePlayer_fire
            bmi movePlayer_fire_retreat
            lda #$e0
            jmp movePlayer_right_add
movePlayer_fire_retreat
            lda #$20
            jmp movePlayer_left_add
movePlayer_right
            lda #$F0             ;2   8
movePlayer_right_add
            clc                        ;2  17
            adc player_hpos            ;3  20
            bvc movePlayer_horiz_save  ;2  22
            adc #$00                   ; carry set
            ldx player_fire
            bne movePlayer_horiz_save
            tax 
            and #$0f
            cmp #$06
            bmi movePlayer_horiz_save_x
movePlayer_right_limit
            lda #$95
            jmp movePlayer_horiz_save ;3  11
movePlayer_left
            lda #$10             ;2  15
movePlayer_left_add
            clc                        ;2  17
            adc player_hpos            ;3  20
            bvc movePlayer_horiz_save  ;2  22
            adc #$0f 
            tax
            and #$0f
            cmp #$03
            bpl movePlayer_horiz_save_x
movePlayer_left_limit
            ldx #$73
movePlayer_horiz_save_x
            txa
movePlayer_horiz_save
            sta player_hpos            ;3  25

movePlayer_vert_start
            lda player_charge_delay
            ora player_charge
            ror
            bcs movePlayer_end   ; move at half speed while fire is down
            lda #$20             ;2  -- replace A
            bit SWCHA            ;3  23
            beq movePlayer_down  ;2  25
            lsr                  ;3  28
            bit SWCHA            ;3  31
            beq movePlayer_up    ;2  33
            jmp movePlayer_end
movePlayer_down
            inc player_vpos      ;5  42
            lda #110             ;2  44
            cmp player_vpos      ;3  47
            bmi movePlayer_up    ;2  49
            jmp movePlayer_end   ;3  52
movePlayer_up
            dec player_vpos      ;5  33 ; exit B
            beq movePlayer_down  ;3  36      
movePlayer_end

            ldx #NUM_RIDERS - 1
moveRider_loop
            lda game_state            ;3   3    
            beq moveRider_init        ;2   5
            dec rider_timer,x         ;6  11
            bpl moveRider_noreset     ;2  13
            lda rider_speed,x         ;4  17
            sta rider_timer,x         ;4  29
            lda rider_move,x          ;-----
            and #$f0
            clc                       ;2  33
            adc rider_hpos,x          ;4  37
            bvs moveRider_dec_hdelay  ;2  39
            sta rider_hpos,x          ;4  43  
            jmp moveRider_noreset     ;3  46
moveRider_dec_hdelay
            adc #$0f              ;2  42
            tay
            and #$0f
            cmp #$0f
            beq moveRider_reset
            sty rider_hpos,x      ;4  50  
            jmp moveRider_noreset ;2  53
moveRider_reset
            ; reset rider
            inc rider_move,x
            lda #RIDER_RESP_START  ;2  56
            sta rider_damaged,x    ;3  59
            sta rider_hpos,x       ;4  --
            lda rider_pattern      ;3  -- ; Galois LFSA
            lsr                    ;2  -- ; see https://samiam.org/blog/20130617.html
            bcc moveRider_skipEor  ;2  --
            eor #$8e               ;2  75
moveRider_skipEor 
            sta rider_pattern      ;3  78 
            and #$07
            tay
            lda RIDER_COLORS,y
            sta rider_colors,x
            beq moveRider_parallax
            tya 
            and #$03
            jmp moveRider_setSpeed
moveRider_parallax
            ldy #<ROCK_0_CTRL
            sty rider_tile,x
            txa
            adc #$02
            lsr
moveRider_setSpeed
            sta rider_speed,x
            jmp moveRider_end
moveRider_init
            lda #<RIDER_SPRITE_START
            lda rider_tile,x
            lda #RIDER_GREEN_TYPE
            sta rider_colors,x
            lda #$70
            sta rider_hpos,x
            lda #$ff
            sta rider_damaged,x
            lda #$10
            sta rider_move,x
moveRider_noreset
moveRider_end
            dex                    ;2   90
            bpl moveRider_loop     ;2   92

animateRider
            dec rider_animate
            bpl animateRider_end
            ldx #RIDER_ANIMATE_SPEED
            stx rider_animate
            ldy #RIDER_GREEN_TYPE
            ldx #NUM_RIDERS - 1
animateRider_loop
            lda rider_colors,x
            beq animateRider_skip_tile
            lda rider_tile,x
            sec
            sbc #48
            cmp #<RIDER_SPRITE_START
            bpl animateRider_save_tile
            lda #<RIDER_SPRITE_2_CTRL
animateRider_save_tile
            sta rider_tile,x
animateRider_skip_tile
            dex
            bpl animateRider_loop
animateRider_end

            inx                    ; x is ff (save instruction)
waitOnVBlank            
            cpx INTIM
            bmi waitOnVBlank

; -----------------------------------
; Display kernels
; 192 scanlines of picture to follow
; ----------------------------------

; horizon kernel(s)
; 36 variable width bands of color gradient 

; horizon + score kernel
; SL 35

            sta WSYNC
            lda #$b0               ;2   2
            sta HMP0               ;3   5
            adc #$20               ;2   7
            sta HMP1               ;3  10
            ldx #$09               ;3  13
horizonScore_resp
            dex                    ;2  15
            bpl horizonScore_resp  ;2  62 (17 + 45)
            sta RESP0              ;3  65
            sta RESP1              ;3  68
; SL 36
            sta WSYNC
            sta HMOVE              ;3   3
            lda #WHITE             ;2   5
            sta COLUP0               ;3  55
            sta COLUP1               ;3  58
            ;ldx #0                 ;2  13 ; end of VBLANK
            inx                    ;2  13 ; end of VBLANK ; optimize code size - x is ff
            stx VBLANK             ;3  16

            ldx #13                ;2  18  
; SL 37 (Display 0)
            sta WSYNC
            lda HORIZON_COLOR,x      ;4   4 
            sta COLUBK               ;3   7
            lda player_score
            and #$0f
            asl
            asl
            asl
            adc #<FONT_0
            sta tmp_addr_1
            lda #>FONT_0
            sta tmp_addr_1 + 1
            lda player_score
            and #$f0
            lsr
            adc #<FONT_0
            sta tmp_addr_0
            lda #>FONT_0
            sta tmp_addr_0 + 1
            ldy #$07

; SL 38-45
horizonScore_Loop
            lda player_health        ;3   3
            sta WSYNC
            sta PF1                  ;3   3
            lda HORIZON_COLOR,x      ;4   7 
            sec                      ;2   9
            sbc game_dark            ;3  12
            sta COLUBK               ;3  15
            lda (tmp_addr_0),y       ;5  20
            sta GRP0                 ;3  23
            lda #RED                 ;2  25
            sta COLUPF               ;3  28
            lda (tmp_addr_1),y       ;5  33
            sta GRP1                 ;3  36
            lda #$00                 ;2  38       
            sta COLUPF               ;3  41
            sta PF1                  ;3  45
            dey                      ;2  47
            bmi horizonScore_End     ;2  49
            tya                      ;2  60
            cmp HORIZON_COUNT,x      ;4  64
            bpl horizonScore_Loop    ;2* 66
            dex                      ;2  68
            jmp horizonScore_Loop    ;3  71

horizonScore_End

; horizon + sun kernel 
; SL 46
            sta WSYNC
            lda HORIZON_COLOR,x      ;4   4 
            sec                      ;2   6
            sbc game_dark            ;3   9
            sta COLUBK               ;3  12
            iny                      ;2  14 ; code opt, y is ff
            sty GRP0                 ;3  17
            sty GRP1                 ;3  20
            ldy #$03                 ;2  22
horizonSun_resp
            dey                      ;2  24
            bpl horizonSun_resp      ;2  41 (26 + 15)
            sta RESP0                ;3  44
            sta RESP1                ;3  47
            ;sta NUSIZ1               ;3  50 ; code opt, should be 0 already
            lda #$10                 ;2  49
            sta HMP0                 ;3  52
            lda #$20                 ;2  54
            sta HMP1                 ;3  57
            lda #1                   ;2  59             
            sta NUSIZ0               ;3  62

; SL 47
horizonGap
            sta WSYNC                ;3   0
            sta HMOVE                ;3   3
            lda HORIZON_COLOR,x      ;4   4 
            sec                      ;2   6
            sbc game_dark            ;3   9
            sta COLUBK               ;3  12
            lda #SUN_RED - 2         ;2  17
            sta tmp_award_color      ;3  20
            lda game_award
            sta tmp_award_inc   
            dex                      ;2  22 ; hardcode

; SL 48 ... 72
            

            ldy #24                  ;2  15
horizonLoop
            sta WSYNC                ;3   0 
            lda HORIZON_COLOR,x      ;4   4 
            sec                      ;2   6
            sbc game_dark            ;3   9
            sta COLUBK               ;3  12
            lda SUN_SPRITE_LEFT,y    ;4  16 
            sta GRP0                 ;3  19
            lda SUN_SPRITE_MIDDLE,y  ;4  23  
            sta GRP1                 ;3  26
            lda #0                   ;2  28
            sta REFP0                ;3  31
            lda tmp_award_color      ;3  34
            adc tmp_award_inc        ;3  37
            sta COLUP0               ;3  40
            sta COLUP1               ;3  43
            lda #8                   ;2  45
            sta REFP0                ;3  48
            dey                      ;2  50
            bmi horizonEnd           ;2  52
            tya                      ;2  54
            cmp HORIZON_COUNT,x      ;4  58
            bpl horizonLoop          ;2* 60
            inc tmp_award_inc
            dex                      ;2  67
            jmp horizonLoop          ;3  70
horizonEnd

;-------------------
; top rail kernel

    ; SC 73 .. 78
            ldx #RAIL_HEIGHT / 2 - 1 ;2  10
rail_A_loop 
            sta WSYNC                ;3   0
            lda MOUNTAIN_PF0,x
            sta PF0
            lda MOUNTAIN_PF1,x
            sta PF1
            lda MOUNTAIN_PF2,x
            sta PF2
            sta WSYNC                ;3   0
            dex                      ;2   2
            bpl rail_A_loop          ;2   4
            inx                      ;2  33 save inst
            stx GRP0                 ;3  36
            stx GRP1                 ;3  39
            stx NUSIZ0               ;3  45
            stx NUSIZ1               ;3  48
            stx HMCLR                ;3  51
            stx player_below_rider   ;3  54
            lda player_charge        ;3  57
            and player_fire          ;3  60
            sta COLUP0               ;3  63
            lda #8                   ;2  65
            sta REFP0                ;3  68 

; ----------------------------------
; playfield kernel 
;
; locating player first
;
    ; SC 79           
            sta WSYNC                ;3   0
            ;ldx #PLAYER_COLOR       ;2   2 save instr (replace with inx)
            ;inx                     ;2   2 x is 00
            lda player_hpos          ;3   3
            and #$0f                 ;2   5
            tay                      ;2   7
player_resp_loop
            dey                      ;2   9
            bpl player_resp_loop     ;2  11 + 25 = 36
            sta RESBL                ;3  39
            sta RESP0                ;3  42
            lda player_hpos          ;3  45
            sta HMP0                 ;3  48
            sta HMBL                 ;3  51

    ; SC 80
            sta WSYNC                ;3   0
            sta HMOVE                ;3   3
            lda player_vpos          ;3   6
            sta player_vdelay        ;3   9
            lda #$30                 ;2  11
            sta PF0                  ;3  14
            ;ldx #$00                ;2  -- save instr (x is 0)
            stx PF1                  ;3  17
            stx PF2                  ;3  20
            ;ldx #BLACK              ;2  -- save inst (x is 0)
            stx COLUBK               ;3  23
            stx HMP0                 ;3  26
            ldx #$d0                 ;2  28 ; adjust for resbl, trying to stay out of hmov window
            stx HMBL                 ;3  31
            lda #RIDER_HEIGHT
            sta player_vindex

;--------------------
; transition to riders kernel
; x loaded with current rider 
; y used for rider graphics index
; sp used for player graphics index

    ; SC 81
            sta WSYNC                ;3   0
            sta HMOVE                ;3   3
            ldx #>RIDER_SPRITE_START ;2   5
            stx tmp_addr_0+1         ;3   8
            stx tmp_addr_1+1         ;3  11
            lda #GREEN               ;2  13
            sta COLUBK               ;3  16
            iny                      ;2  18 ; save instr (y is ff)
            ldx #NUM_RIDERS - 1      ;2  20
            sty HMBL                 ;3  23
riders_start
            jmp rider_A_prestart     ;3  32

    ; SC 82 .. 216 (27 * 5)

riders_end

;--------------------
; bottom rail kernel
;

            ldx #RAIL_HEIGHT - 1
rail_B_loop
            dex
            sta WSYNC
            bpl rail_B_loop

    ; SC 217
            sta WSYNC
            ;lda #BLACK            ;2   2 ; code size opt 
            inx                   ;2   2  ; x is ff
            stx COLUBK            ;3   5
            stx REFP0             ;2   7
            stx NUSIZ0            ;2   9
            stx NUSIZ1            ;2  11
            lda #WHITE            ;2  13
            sta COLUP0            ;3  16
            sta COLUP1            ;3  19
            ldx #$07              ;2  21 
logo_resp_loop
            dex                   ;2  23
            bpl logo_resp_loop    ;2  60 (25 + 7 * 5)
            sta RESP0             ;3  63
            sta RESP1             ;3  66

    ; SC 218 - 224

            ldx #LOGO_HEIGHT - 1
logo_loop 
            sta WSYNC
            lda DC21_0,x
            sta GRP0
            lda DC21_1,x
            sta GRP1
            dex
            bpl logo_loop

    ; SC 225 - 255
    ; 30 lines of overscan to follow            

            ldx #30
doOverscan  sta WSYNC               ; wait a scanline
            dex
            bne doOverscan
            lda #$01
            bit SWCHB
            bne gameCheckHealth
            jmp Reset

gameCheckHealth
            lda player_health
            beq gameEnd
gameCheckWin
            lda player_score
            cmp #WINNING_SCORE
            bne gameContinue
            dec game_award
            lda #$01          
            and player_health
            beq gameEnd
            dec game_dark
gameEnd
            ;lda #0 optimization x is 0
            stx game_state
gameContinue

frameEnd
            jmp newFrame

;-----------------------------------------------------------------------------------
; Rider Kernels
; Riders are drawn using the following strategy
;
;   prestart - at end of previous kernel, check if the rider is on left or right edge
;              (will trigger short versus long strobe kernels) 
;   start    - 1 scanline to strobe resp1 and set hmov1
;   hmov     - 1 scanline to do horizontal HMOV and set up graphics
;   loop     - RIDER_HEIGHT scanlines of graphics
;   
;   the additional complication is the player resulting in at least two variants of each kernel
;   
;   rider A pattern - we are drawing only the rider
;                     every A kernel decrements player_vdelay looking for a transition to B
;   rider B pattern - we draw the player and the rider
;                     player position is strobed before we start drawing riders
;                     player graphics are pushed onto the stack during vblank
;                     every B kernel pulls those graphics off the stack
;                           1 byte of player 0 graphics 
;                           1 byte containing player 0 HMOV0 and NUSIZ0 data 
;                           1 byte of processor status to signal whether to move back to A 
;
;   A to B transitions - enable ball graphics (used for the spear)
;   B to A transitions - disable ball graphics
;
;   each kernel therefore has multiple versions...
;         A vs B pattern
;         the strobe kernels have additional short and long versions
;         transition kernels for crossing between A and B versions
;         a few transitions are very tight...
;           ... and have to splice into the middle of kernels 
;           ... which is super fun
;         
;   labels are used to try and keep the spaghetti from getting out of control:
;        kernels: rider_(A|B)_(kernel)...
;        transitions are named by their target: rider_(A_to_B)_(kernel)...
;
; possible improvements:
;  - could save a third of stack space by not pushing processor status and instead tracking
;    stack pointer ... tradeoff is we would have to manage x register, currently used hold rider #
;  - use of the x register to hold rider # seems wasteful (we basically never touch it in 
;    any kernel)
;
; rider strobe timings (for reference)
; RESPx STROBE CHART
; A Y0 SC 22 PP  12
; A Y1 SC 27 PP  27
; A Y2 SC 32 PP  42
; A Y3 SC 37 PP  57
; A Y4 SC 42 PP  72
; A Y5 SC 47 PP  87
; A Y6 SC 52 PP 102
; A Y7 SC 57 PP 117
; A Y8 SC 62 PP 132
; A Y9 SC 67 PP 147

;-----------------------------------------------------------------------------------
; Rider A Pattern
; rider only, waiting for player

rider_A_start_l
            sta WSYNC                ;3   0 
            sta HMOVE                ;3   3
            tay                      ;2   5
            dec player_vdelay        ;5  10
            beq rider_A_to_B_start_l ;2  12
rider_A_resp_l; strobe resp
            dey                      ;2  14
            bpl rider_A_resp_l       ;2+ 16 (16 + 8 * 5)
            lda tmp                  ;3  19
            sta HMP1                 ;3  22
            sta RESP1                ;3  25 
            jmp rider_A_hmov         ;3  68 

rider_A_to_B_start_l
            dey                      ;2  15
            dey                      ;2  17
            lda player_fire          ;3  20
            bne rider_A_to_B_resp_l  ;2  22 
            lda #$ff                 ;2  24
            sta ENABL                ;3  27
            sta HMBL                 ;3  30
            dey                      ;2  32
            dey                      ;2  34
            dey                      ;2  36
            SLEEP 2                  ;2  38 timing shim
rider_A_to_B_resp_l          
            dey                      ;2  40 / 25
            bpl rider_A_to_B_resp_l  ;2+ 57 / 57 (27 / 42 + 6 * 5 / 3 * 5)
            SLEEP 2                  ;2  59 timing shim
            lda tmp                  ;3  62
            sta RESP1                ;3  65 
            sta HMP1                 ;3  68
            jmp rider_B_hmov         ;3  71

rider_A_prestart
            lda rider_hpos,x        ;4  --
            sta tmp                 ;3  --
            and #$0f                ;2  --
            cmp #$05                ;2  --
            bpl rider_A_start_l     ;2  --

rider_A_start
            ; locate p1
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3
            tay                     ;2   5
            iny                     ;2   7
rider_A_resp; strobe resp 
            dey                     ;2   9 
            bpl rider_A_resp        ;2+ 36 (11 + 5 * 5)
            lda tmp                 ;3  39
            sta HMP1                ;3  42
            sta RESP1               ;3  50 
            dec player_vdelay       ;5  55
            bne rider_A_hmov        ;2  57
rider_A_to_B_hmov
            lda player_fire           ;3  60
            bne rider_A_to_B_hmov_jmp ;2  62
            sty HMBL                  ;3  65  ; trick - y is $ff
            sty ENABL                 ;3  68
rider_A_to_B_hmov_jmp
            jmp rider_B_hmov          ;3  71

rider_A_hmov; locating rider horizontally 2
            sta WSYNC                     ;3   0 
            sta HMOVE                     ;3   3 ; process hmoves
rider_A_hmov_0; from rider B
            lda rider_colors,x            ;4   7
            sta COLUP1                    ;3  10
            lda rider_tile,x              ;4  14
            sta tmp_addr_0                ;3  17
            clc                           ;2  19
            adc #24                       ;2  21
            sta tmp_addr_1                ;3  24
            lda #$0                       ;2  26
            ldy #RIDER_HEIGHT - 1         ;2  28
            dec player_vdelay             ;5  33
            sta CXCLR                     ;3  36 prep for collision
            sta HMP1                      ;3  39
            beq rider_A_to_B_loop         ;2  41

rider_A_loop;
            sta WSYNC               ;3   0
            sta HMOVE               ;3   3 ; process hmoves
rider_A_loop_body:
            lda (tmp_addr_1),y      ;5   8 ; p1 draw
            sta GRP1                ;3  11
            lda (tmp_addr_0),y      ;5  16
            sta NUSIZ1              ;3  19
            dec player_vdelay       ;5  24
            sta HMP1                ;3  27
            beq rider_A_to_B_loop_a ;2  29
rider_A_loop_a;
            dey                     ;5  34 73
            bpl rider_A_loop        ;2  36 75

rider_A_end
            sta WSYNC               ;3   0
            sta HMOVE               ;3   3
            lda CXPPMM              ;2   5   
            sta rider_hit,X         ;4   9
            dec player_vdelay       ;5  14
            bne rider_A_end_a       ;2  16
            jsr rider_A_to_B_sub    ;25 41
            dex                     ;2  43 ; optimization, never end riders on B transition
            jmp rider_B_prestart    ;3  46
        
rider_A_end_a
            dex                     ;2  19 / 50 from b
            bpl rider_A_prestart    ;2  21 / 52
            jmp riders_end          ;3  24 / 55

rider_A_to_B_sub
            lda player_fire          ;3 + 3
            bne rider_A_to_B_sub_rts ;2 + 5
            lda #$ff                 ;2 + 7
            sta HMBL                 ;3 +10
            sta ENABL                ;3 +13
rider_A_to_B_sub_rts
            rts                      ;6 +19

rider_A_to_B_loop
            jsr rider_A_to_B_sub    ;25 67
            jmp rider_B_loop        ;3  70

rider_A_to_B_loop_a
            tya                     ;2  32
            sbc #RIDER_HIT_BOX      ;2  34
            sta player_below_rider  ;3  37
            jsr rider_A_to_B_sub    ;25 62
            jmp rider_B_loop_a      ;3  65

;-----------------------------------------------------------------------------------
; Rider B Pattern 
; player + rider on same line


rider_B_start_0
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3 ; process hmoves
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            iny                     ;2  22 y is ff + timing shim + readying COLUPF for after jump
            sta RESP1               ;3  25  
            sta NUSIZ0              ;3  28
            jmp rider_B_resp_end_0  ;3  36

rider_B_start_l
            ; locate p1 at right edge of screen
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
            ldy rider_hpos,x        ;4  27
            sta HMP0                ;3  30
            sty HMP1                ;3  33
            lda tmp                 ;3  36
            sbc #$05                ;2  38 ; take advantage carry .. set? 
            tay                     ;2  40
rider_B_resp_l; strobe resp
            dey                     ;2  42
            bpl rider_B_resp_l      ;2  54 (44 + 2 * 5)
            iny                     ;2  56 ; make y be 0
            sty COLUPF              ;3  59
            SLEEP 3                 ;3  62
            sty RESP1               ;3  65             
            dec player_vindex       ;5  70
            bne rider_B_hmov        ;2  72

rider_B_to_A_hmov
            sta WSYNC               ;3   0 ; may have enough cyles not to interleave
            sta HMOVE               ;3   3 ; transition from B_to_A
            sty ENABL               ;3   9 ; interleave with rider_A_hmov
            jmp rider_A_hmov_0      ;3  12

rider_B_prestart
            iny                    ;2  46 / 48 from a optimization, y is ff
            sty COLUPF             ;3  47
            lda rider_hpos,x       ;4  51
            and $0f                ;2  53
            tay                    ;2  55
            dey                    ;2  57
            bmi rider_B_start_0    ;2  62
            sty tmp                ;3  65
            cpy #$05               ;2  67
            bpl rider_B_start_l    ;2  69 / 71
rider_B_start_n
            ; locate p1
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3 ; process hmoves
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
rider_B_resp; strobe resp
            dey                     ;2  25
            bpl rider_B_resp        ;2  47  27 + 4 * 5
            sta RESP1               ;3  49
            iny                     ;2  51 y is 0, save instr
rider_B_resp_end_0
            sta HMP0                ;3  54
            lda rider_hpos,x        ;4  58
            sta HMP1                ;3  61
            dec player_vindex       ;5  66 ; exit B
            sty COLUPF              ;3  69
            beq rider_B_to_A_hmov   ;2  71

rider_B_hmov; locating rider horizontally
            sta WSYNC               ;3   0 
            sta HMOVE               ;3   3 ; process hmoves
rider_B_hmov_a
            pla                     ;4   7 / 11 (from a)
            sta GRP0                ;3  10 
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
            sta HMP0                ;3  26
            lda rider_colors,x      ;4  30
            sta COLUP1              ;3  33
            lda rider_tile,x        ;4  37   
            sta tmp_addr_0          ;3  40
            clc                     ;2  42
            adc #24                 ;2  44 / 51
            sta tmp_addr_1          ;3  47
            lda #$00                ;2  49
            sta HMP1                ;3  52 / 59
            sta CXCLR               ;3  55 prep for collision
            sta COLUPF              ;3  58
            ldy #RIDER_HEIGHT - 1   ;2  60
            dec player_vindex       ;5  65 ; exit B
            bne rider_B_loop        ;2  67 / 74 (from a)
            sta ENABL               ;3  70 ; a already 0 
            jmp rider_A_loop        ;3  73

rider_B_loop  
            sta WSYNC               ;3   0
            sta HMOVE               ;3   3 ; process hmoves
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
            sta HMP0                ;3  26
            lda (tmp_addr_1),y      ;5  31 ; p1 draw
            sta GRP1                ;3  34
            lda (tmp_addr_0),y      ;5  39
            sta NUSIZ1              ;3  42
            sta HMP1                ;3  45
            lda #$0                 ;2  47
            dec player_vindex       ;5  52 ; exit B
            sta COLUPF              ;3  55
            beq rider_B_to_A_loop_a ;2  57
rider_B_loop_a
            dey                     ;5  62
            bpl rider_B_loop        ;2  64

rider_B_end
            sta WSYNC               ;3   0
            sta HMOVE               ;3   3 ; process hmoves
            pla                     ;4   7
            sta GRP0                ;3  10
            lda player_charge       ;3  13
            sta COLUPF              ;3  16
            pla                     ;4  20
            sta NUSIZ0              ;3  23
            sta HMP0                ;3  26
            lda CXPPMM              ;2  28     
            sta rider_hit,x         ;4  32
            dec player_vindex       ;5  37  
            beq rider_B_to_A_end_a  ;2  39
rider_B_end_a
            dex                      ;2  41
            ;bmi rider_B_end_jmp     ;2  -- ; optimization - can't end on B so no check
            jmp rider_B_prestart     ;3  44

rider_B_to_A_loop_a; 
            sta ENABL                 ;3  59
            jmp rider_A_loop_a        ;3  62

rider_B_to_A_end_a
            iny                     ;2  42 optimization, y should be ff
            sty ENABL               ;3  45
            sty COLUPF              ;3  48
            jmp rider_A_end_a       ;3  51

;-----------------------------------------------------------------------------------
; sprite graphics
;   ORG $F600

FONT_0
        byte $3c,$7e,$66,$66,$66,$66,$7e,$3c; 8
FONT_1
        byte $7e,$7e,$18,$18,$18,$18,$78,$78; 8
FONT_2
        byte $7e,$7e,$40,$7e,$7e,$6,$7e,$7e; 8
FONT_3
        byte $7e,$7e,$6,$7e,$7e,$6,$7e,$7e; 8
FONT_4
        byte $6,$6,$6,$7e,$7e,$66,$66,$66; 8
FONT_5
        byte $7e,$7e,$6,$7e,$7e,$60,$7e,$7e; 8
FONT_6
        byte $7e,$7e,$66,$7e,$7e,$60,$7e,$7e; 8
FONT_7
        byte $6,$6,$6,$6,$6,$6,$7e,$7e; 8
FONT_8
        byte $7e,$7e,$66,$7e,$7e,$66,$7e,$7e; 8
FONT_9
        byte $6,$6,$6,$7e,$7e,$66,$7e,$7e; 8

SUN_SPRITE_LEFT ; 25
        byte $ff,$ff,$ff,$ff,$7f,$7f,$7f,$7f,$3f,$3f,$3f,$1f,$1f,$f,$f,$7,$3,$1,$0,$0,$0,$0,$0,$0,$0
SUN_SPRITE_MIDDLE ; 25
        byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff,$3c,$0,$0,$0,$0,$0

HORIZON_COLOR ; 14 bytes
        byte CLOUD_ORANGE - 2, CLOUD_ORANGE, CLOUD_ORANGE + 2, CLOUD_ORANGE + 4, SKY_YELLOW, SKY_YELLOW + 2, SKY_YELLOW + 4, SKY_YELLOW + 2, SKY_YELLOW, WHITE_WATER, SKY_BLUE + 8, SKY_BLUE + 4, SKY_BLUE + 2, SKY_BLUE 
HORIZON_COUNT ; 14 bytes
        byte $0, $2, $4, $6, $7, $8, $b, $13, $16, $17, $18, $0, $2, $4 

MOUNTAIN_PF0 ; 4
        byte $ff, $f0, $f0
MOUNTAIN_PF1 ; 4
        byte $ff, $f3, $c0
MOUNTAIN_PF2 ; 4
        byte $ff, $3f, $0f

RIDER_COLORS ; 8 bytes
        byte BLACK, BLACK, GREEN, GREEN, BROWN, RED, WHITE, YELLOW

DC21_0 ; 6 bytes
        byte $0,$c6,$a8,$a8,$a8,$c6; 6

;   ORG $F700

DC21_1 ; 6 bytes
        byte $0,$e8,$88,$e8,$28,$e8; 6

RIDER_SPRITE_START
RIDER_SPRITE_0_CTRL
    byte $5,$5,$f5,$f5,$5,$5,$f5,$f5,$5,$17,$f5,$7,$f5,$a7,$45,$5,$15,$5,$50,$0,$10,$0,$0,$0; 24
RIDER_SPRITE_0_GRAPHICS
    byte $0,$51,$49,$45,$77,$67,$6f,$7f,$7f,$f8,$ff,$fc,$ff,$fe,$f7,$ee,$ce,$4d,$3c,$38,$f0,$60,$90,$90; 24
RIDER_SPRITE_1_CTRL
    byte $5,$5,$15,$35,$f5,$f5,$5,$15,$5,$f5,$f7,$5,$f7,$a7,$45,$5,$15,$25,$40,$0,$0,$0,$0,$0; 24
RIDER_SPRITE_1_GRAPHICS
    byte $0,$9f,$af,$9e,$86,$c6,$ef,$fe,$fe,$ff,$f8,$ff,$fc,$fe,$f7,$ee,$cd,$9c,$78,$70,$f0,$60,$90,$90; 24
RIDER_SPRITE_2_CTRL
    byte $5,$5,$f5,$5,$15,$15,$5,$5,$5,$17,$f5,$7,$f5,$a7,$45,$5,$15,$5,$40,$0,$20,$0,$0,$0; 24
RIDER_SPRITE_2_GRAPHICS
    byte $0,$44,$22,$a7,$a3,$e7,$67,$7f,$7f,$f8,$ff,$fc,$ff,$fe,$f7,$ee,$ce,$4d,$1e,$3c,$60,$90,$90,$0; 24
RIDER_SPRITE_3_CTRL
    byte $0,$0,$b5,$f5,$f5,$5,$f7,$15,$5,$27,$5,$7,$f5,$f7,$e5,$5,$f5,$5,$15,$15,$50,$0,$0,$0; 24
RIDER_SPRITE_3_GRAPHICS
    byte $0,$33,$4a,$4e,$43,$47,$f8,$e7,$ff,$f8,$fe,$f8,$fe,$f8,$7f,$fc,$fe,$fe,$ce,$96,$cf,$6,$9,$9; 24
ROCK_0_CTRL
    byte $0,$7,$27,$7,$25,$5,$5,$5,$5,$5,$5,$5,$25,$f5,$15,$10,$0,$0,$0,$0,$0,$10,$0,$30; 24
ROCK_0_GRAPHICS
    byte $0,$fc,$f8,$f8,$ff,$7e,$fc,$fe,$fe,$7e,$fc,$fe,$f8,$fc,$f8,$ff,$ff,$fe,$ff,$7e,$fe,$fc,$f8,$c0; 24
                
;-----------------------------------------------------------------------------------
; the CPU reset vectors

    ORG $F7FA

    .word Reset          ; NMI
    .word Reset          ; RESET
    .word Reset          ; IRQ

    END