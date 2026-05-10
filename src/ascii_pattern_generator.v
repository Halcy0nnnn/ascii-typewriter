`default_nettype none

module ascii_pattern_generator (
    input  wire       clk,          // NEW: Required for animation memory
    input  wire       rst_n,        // NEW: Required for animation memory
    input  wire [9:0] h_count,
    input  wire [9:0] v_count,
    input  wire       video_active,
    output reg  [1:0] r,
    output reg  [1:0] g,
    output reg  [1:0] b
);

    // --------------------------------------------------------
    // 0. Animation Hardware State Machine
    // --------------------------------------------------------
    // A single pulse generated exactly once per frame (60 times a second)
    wire frame_tick = (h_count == 10'd0) && (v_count == 10'd0);

    reg [1:0] anim_state;
    reg [4:0] visible_chars; // How many characters to draw (0 to 17)
    reg [7:0] delay_timer;   // Used to count frames for pauses
    
    reg [5:0] blink_timer;   // Independent timer for the cursor blink
    reg       blink_state;   // 1 = cursor visible, 0 = hidden

    localparam STATE_TYPING = 2'd0;
    localparam STATE_PAUSED = 2'd1;
    localparam STATE_ERASING = 2'd2;
    localparam STATE_IDLE   = 2'd3;

    always @(posedge clk) begin
        if (!rst_n) begin
            anim_state    <= STATE_IDLE;
            visible_chars <= 5'd0;
            delay_timer   <= 8'd0;
            blink_timer   <= 6'd0;
            blink_state   <= 1'b1;
        end else if (frame_tick) begin
            // 1. Handle the Blinking Cursor (toggles every 30 frames / 0.5 sec)
            if (blink_timer >= 6'd30) begin
                blink_timer <= 0;
                blink_state <= ~blink_state;
            end else begin
                blink_timer <= blink_timer + 1;
            end

            // 2. Handle the Typewriter Sequence
            case (anim_state)
                STATE_TYPING: begin
                    if (delay_timer >= 8'd6) begin // Speed: Type 1 char every 6 frames
                        delay_timer <= 0;
                        if (visible_chars == 5'd17)
                            anim_state <= STATE_PAUSED;
                        else
                            visible_chars <= visible_chars + 1;
                    end else begin
                        delay_timer <= delay_timer + 1;
                    end
                end
                STATE_PAUSED: begin
                    if (delay_timer >= 8'd180) begin // Speed: Wait 180 frames (3 seconds)
                        delay_timer <= 0;
                        anim_state <= STATE_ERASING;
                    end else begin
                        delay_timer <= delay_timer + 1;
                    end
                end
                STATE_ERASING: begin
                    if (delay_timer >= 8'd4) begin // Speed: Erase slightly faster (4 frames)
                        delay_timer <= 0;
                        if (visible_chars == 5'd0)
                            anim_state <= STATE_IDLE;
                        else
                            visible_chars <= visible_chars - 1;
                    end else begin
                        delay_timer <= delay_timer + 1;
                    end
                end
                STATE_IDLE: begin
                    if (delay_timer >= 8'd45) begin // Speed: Wait short bit before restarting
                        delay_timer <= 0;
                        anim_state <= STATE_TYPING;
                    end else begin
                        delay_timer <= delay_timer + 1;
                    end
                end
            endcase
        end
    end

    // --------------------------------------------------------
    // 1. Grid Math & Positioning
    // --------------------------------------------------------
    wire in_line1 = (v_count >= 10'd160) && (v_count < 10'd224) && 
                    (h_count >= 10'd32)  && (h_count < 10'd608);
                    
    // Note: Extended line2 width to 640 so the cursor can draw AFTER the 'w'
    wire in_line2 = (v_count >= 256) && (v_count < 320) && 
                    (h_count >= 64)  && (h_count < 640); 

    wire [9:0] local_x = in_line1 ? (h_count - 10'd32) :
                         in_line2 ? (h_count - 10'd64) : 10'd0;
                         
    wire [9:0] local_y = in_line1 ? (v_count - 10'd160) :
                         in_line2 ? (v_count - 10'd256) : 10'd0;

    wire [3:0] char_idx = local_x[9:6]; 

    // Create a 0-17 global index for the whole sentence to compare against the state machine
    wire [4:0] global_idx = in_line1 ? {1'b0, char_idx} : 
                            in_line2 ? (char_idx + 5'd9) : 5'd31;

    // --------------------------------------------------------
    // 2. Combinatorial String Map
    // --------------------------------------------------------
    reg [7:0] macro_shape_char;
    always @(*) begin
        macro_shape_char = 8'h20; 
        if (in_line1) begin
            case (char_idx)
                4'd0: macro_shape_char = "A"; 4'd1: macro_shape_char = "s";
                4'd2: macro_shape_char = " "; 4'd3: macro_shape_char = "A";
                4'd4: macro_shape_char = "b"; 4'd5: macro_shape_char = "o";
                4'd6: macro_shape_char = "v"; 4'd7: macro_shape_char = "e";
                4'd8: macro_shape_char = ",";
            endcase
        end else if (in_line2) begin
            case (char_idx)
                4'd0: macro_shape_char = "S"; 4'd1: macro_shape_char = "o";
                4'd2: macro_shape_char = " "; 4'd3: macro_shape_char = "B";
                4'd4: macro_shape_char = "e"; 4'd5: macro_shape_char = "l";
                4'd6: macro_shape_char = "o"; 4'd7: macro_shape_char = "w";
            endcase
        end
    end

    // DYNAMIC CHARACTER INJECTOR: Overrides the letter with an '_' if it's the active cursor!
    wire [7:0] target_char = (global_idx < visible_chars) ? macro_shape_char :
                             ((global_idx == visible_chars) && blink_state) ? "_" : 8'h20;

    // --------------------------------------------------------
    // 2.5 Pseudo-Random Micro Character Selection
    // --------------------------------------------------------
    wire [2:0] prng_hash = h_count[7:5] ^ v_count[6:4] ^ {h_count[9:8], h_count[3]} ^ {v_count[8:7], v_count[3]};
    reg [7:0] random_micro_char;
    always @(*) begin
        case (prng_hash)
            3'd0: random_micro_char = "A"; 3'd1: random_micro_char = "S";
            3'd2: random_micro_char = "o"; 3'd3: random_micro_char = "v";
            3'd4: random_micro_char = "e"; 3'd5: random_micro_char = "B";
            3'd6: random_micro_char = "s"; 3'd7: random_micro_char = "w";
        endcase
    end

    // --------------------------------------------------------
    // 3. Independent Font ROM Lookups
    // --------------------------------------------------------
    wire [2:0] micro_x = local_x[2:0];
    wire [2:0] micro_y = local_y[2:0];
    wire [2:0] macro_x = local_x[5:3]; 
    wire [2:0] macro_y = local_y[5:3]; 
    
    reg [7:0] micro_row;
    reg [7:0] macro_row; 

    // A. Generate the MACRO row based on the string map + cursor override
    always @(*) begin
        macro_row = 8'b00000000;
        case (target_char)
            "A": case (macro_y)
                    3'd0: macro_row = 8'b00011000; 3'd1: macro_row = 8'b00100100;
                    3'd2: macro_row = 8'b01000010; 3'd3: macro_row = 8'b01000010;
                    3'd4: macro_row = 8'b01111110; 3'd5: macro_row = 8'b01000010;
                    3'd6: macro_row = 8'b01000010; 3'd7: macro_row = 8'b00000000;
                 endcase
            "s": case (macro_y)
                    3'd0: macro_row = 8'b00000000; 3'd1: macro_row = 8'b00111100;
                    3'd2: macro_row = 8'b01100000; 3'd3: macro_row = 8'b00111100;
                    3'd4: macro_row = 8'b00000110; 3'd5: macro_row = 8'b01100110;
                    3'd6: macro_row = 8'b00111100; 3'd7: macro_row = 8'b00000000;
                 endcase
            "b": case (macro_y)
                    3'd0: macro_row = 8'b01000000; 3'd1: macro_row = 8'b01000000;
                    3'd2: macro_row = 8'b01000000; 3'd3: macro_row = 8'b01011100;
                    3'd4: macro_row = 8'b01100010; 3'd5: macro_row = 8'b01100010;
                    3'd6: macro_row = 8'b01011100; 3'd7: macro_row = 8'b00000000;
                 endcase
            "o": case (macro_y)
                    3'd0: macro_row = 8'b00000000; 3'd1: macro_row = 8'b00000000;
                    3'd2: macro_row = 8'b00111100; 3'd3: macro_row = 8'b01000010;
                    3'd4: macro_row = 8'b01000010; 3'd5: macro_row = 8'b01000010;
                    3'd6: macro_row = 8'b00111100; 3'd7: macro_row = 8'b00000000;
                 endcase
            "v": case (macro_y)
                    3'd0: macro_row = 8'b00000000; 3'd1: macro_row = 8'b00000000;
                    3'd2: macro_row = 8'b01000010; 3'd3: macro_row = 8'b01000010;
                    3'd4: macro_row = 8'b00100100; 3'd5: macro_row = 8'b00100100;
                    3'd6: macro_row = 8'b00011000; 3'd7: macro_row = 8'b00000000;
                 endcase
            "e": case (macro_y)
                    3'd0: macro_row = 8'b00000000; 3'd1: macro_row = 8'b00000000;
                    3'd2: macro_row = 8'b00111100; 3'd3: macro_row = 8'b01000010;
                    3'd4: macro_row = 8'b01111110; 3'd5: macro_row = 8'b01000000;
                    3'd6: macro_row = 8'b00111100; 3'd7: macro_row = 8'b00000000;
                 endcase
            ",": case (macro_y)
                    3'd0: macro_row = 8'b00000000; 3'd1: macro_row = 8'b00000000;
                    3'd2: macro_row = 8'b00000000; 3'd3: macro_row = 8'b00000000;
                    3'd4: macro_row = 8'b00011000; 3'd5: macro_row = 8'b00011000;
                    3'd6: macro_row = 8'b00001000; 3'd7: macro_row = 8'b00010000;
                 endcase
            "S": case (macro_y)
                    3'd0: macro_row = 8'b00111100; 3'd1: macro_row = 8'b01000010;
                    3'd2: macro_row = 8'b01000000; 3'd3: macro_row = 8'b00111100;
                    3'd4: macro_row = 8'b00000010; 3'd5: macro_row = 8'b01000010;
                    3'd6: macro_row = 8'b00111100; 3'd7: macro_row = 8'b00000000;
                 endcase
            "B": case (macro_y)
                    3'd0: macro_row = 8'b01111100; 3'd1: macro_row = 8'b01000010;
                    3'd2: macro_row = 8'b01000010; 3'd3: macro_row = 8'b01111100;
                    3'd4: macro_row = 8'b01000010; 3'd5: macro_row = 8'b01000010;
                    3'd6: macro_row = 8'b01111100; 3'd7: macro_row = 8'b00000000;
                 endcase
            "l": case (macro_y)
                    3'd0: macro_row = 8'b00110000; 3'd1: macro_row = 8'b00010000;
                    3'd2: macro_row = 8'b00010000; 3'd3: macro_row = 8'b00010000;
                    3'd4: macro_row = 8'b00010000; 3'd5: macro_row = 8'b00010000;
                    3'd6: macro_row = 8'b00111000; 3'd7: macro_row = 8'b00000000;
                 endcase
            "w": case (macro_y)
                    3'd0: macro_row = 8'b00000000; 3'd1: macro_row = 8'b00000000;
                    3'd2: macro_row = 8'b01000010; 3'd3: macro_row = 8'b01000010;
                    3'd4: macro_row = 8'b01011010; 3'd5: macro_row = 8'b01100110;
                    3'd6: macro_row = 8'b01000010; 3'd7: macro_row = 8'b00000000;
                 endcase
            "_": case (macro_y)
                    // The bottom row forms the solid underscore
                    3'd7: macro_row = 8'b11111111; 
                 endcase
        endcase
    end

    // B. Generate the MICRO row based on the PRNG hash
    always @(*) begin
        micro_row = 8'b00000000;
        case (random_micro_char)
            "A": case (micro_y)
                    3'd0: micro_row = 8'b00000000; 3'd1: micro_row = 8'b00011000;
                    3'd2: micro_row = 8'b00100100; 3'd3: micro_row = 8'b01000010;
                    3'd4: micro_row = 8'b01111110; 3'd5: micro_row = 8'b01000010;
                    3'd6: micro_row = 8'b01000010; 3'd7: micro_row = 8'b00000000;
                 endcase
            "s": case (micro_y)
                    3'd0: micro_row = 8'b00000000; 3'd1: micro_row = 8'b00111100;
                    3'd2: micro_row = 8'b01100000; 3'd3: micro_row = 8'b00111100;
                    3'd4: micro_row = 8'b00000110; 3'd5: micro_row = 8'b01100110;
                    3'd6: micro_row = 8'b00111100; 3'd7: micro_row = 8'b00000000;
                 endcase
            "o": case (micro_y)
                    3'd0: micro_row = 8'b00000000; 3'd1: micro_row = 8'b00000000;
                    3'd2: micro_row = 8'b00111100; 3'd3: micro_row = 8'b01000010;
                    3'd4: micro_row = 8'b01000010; 3'd5: micro_row = 8'b01000010;
                    3'd6: micro_row = 8'b00111100; 3'd7: micro_row = 8'b00000000;
                 endcase
            "v": case (micro_y)
                    3'd0: micro_row = 8'b00000000; 3'd1: micro_row = 8'b00000000;
                    3'd2: micro_row = 8'b01000010; 3'd3: micro_row = 8'b01000010;
                    3'd4: micro_row = 8'b00100100; 3'd5: micro_row = 8'b00100100;
                    3'd6: micro_row = 8'b00011000; 3'd7: micro_row = 8'b00000000;
                 endcase
            "e": case (micro_y)
                    3'd0: micro_row = 8'b00000000; 3'd1: micro_row = 8'b00000000;
                    3'd2: micro_row = 8'b00111100; 3'd3: micro_row = 8'b01000010;
                    3'd4: micro_row = 8'b01111110; 3'd5: micro_row = 8'b01000000;
                    3'd6: micro_row = 8'b00111100; 3'd7: micro_row = 8'b00000000;
                 endcase
            "S": case (micro_y)
                    3'd0: micro_row = 8'b00111100; 3'd1: micro_row = 8'b01000010;
                    3'd2: micro_row = 8'b01000000; 3'd3: micro_row = 8'b00111100;
                    3'd4: micro_row = 8'b00000010; 3'd5: micro_row = 8'b01000010;
                    3'd6: micro_row = 8'b00111100; 3'd7: micro_row = 8'b00000000;
                 endcase
            "B": case (micro_y)
                    3'd0: micro_row = 8'b01111100; 3'd1: micro_row = 8'b01000010;
                    3'd2: micro_row = 8'b01000010; 3'd3: micro_row = 8'b01111100;
                    3'd4: micro_row = 8'b01000010; 3'd5: micro_row = 8'b01000010;
                    3'd6: micro_row = 8'b01111100; 3'd7: micro_row = 8'b00000000;
                 endcase
            "w": case (micro_y)
                    3'd0: micro_row = 8'b00000000; 3'd1: micro_row = 8'b00000000;
                    3'd2: micro_row = 8'b01000010; 3'd3: micro_row = 8'b01000010;
                    3'd4: micro_row = 8'b01011010; 3'd5: micro_row = 8'b01100110;
                    3'd6: micro_row = 8'b01000010; 3'd7: micro_row = 8'b00000000;
                 endcase
        endcase
    end

    // Extract the active pixel
    wire micro_pixel_active = micro_row[3'd7 - micro_x];
    wire macro_pixel_active = macro_row[3'd7 - macro_x];

    // --------------------------------------------------------
    // 4. Color Output Logic
    // --------------------------------------------------------
    always @(*) begin
        r = 2'b00; g = 2'b00; b = 2'b00;
        
        if (video_active) begin
            if ((in_line1 || in_line2) && macro_pixel_active && micro_pixel_active) begin
                g = 2'b11; // Bright Green text
            end else begin
                b = 2'b01; // Dim Blue background
            end
        end
    end

endmodule