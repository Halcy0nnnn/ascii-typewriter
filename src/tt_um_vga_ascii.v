`default_nettype none

module tt_um_vga_ascii (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    // --------------------------------------------------------
    // Internal Wires
    // --------------------------------------------------------
    wire [9:0] h_count;
    wire [9:0] v_count;
    wire       hsync;
    wire       vsync;
    wire       video_active;
    wire [1:0] r;
    wire [1:0] g;
    wire [1:0] b;

    // --------------------------------------------------------
    // Instantiations
    // --------------------------------------------------------
    
    // 1. Timing Controller
    vga_sync_generator sync_gen (
        .clk(clk),
        .rst_n(rst_n),
        .h_count(h_count),
        .v_count(v_count),
        .hsync(hsync),
        .vsync(vsync),
        .video_active(video_active)
    );

    // 2. Rendering Engine
    ascii_pattern_generator pattern_gen (
        .clk(clk),                  // <--- ADD THIS
        .rst_n(rst_n),              // <--- ADD THIS
        .h_count(h_count),
        .v_count(v_count),
        .video_active(video_active),
        .r(r),
        .g(g),
        .b(b)
    );

    // --------------------------------------------------------
    // Tiny Tapeout VGA PMOD Pin Mapping
    // --------------------------------------------------------
    // The standard TT VGA PMOD expects a 6-bit RGB (2 bits per color)
    // plus HSYNC and VSYNC mapped to the dedicated output pins.
    
    assign uo_out[0] = r[1];    // R1 (Red MSB)
    assign uo_out[1] = g[1];    // G1 (Green MSB)
    assign uo_out[2] = b[1];    // B1 (Blue MSB)
    assign uo_out[3] = vsync;   // VSYNC
    assign uo_out[4] = r[0];    // R0 (Red LSB)
    assign uo_out[5] = g[0];    // G0 (Green LSB)
    assign uo_out[6] = b[0];    // B0 (Blue LSB)
    assign uo_out[7] = hsync;   // HSYNC

    // --------------------------------------------------------
    // Unused Pins & Safe Defaults
    // --------------------------------------------------------
    // It is critical in ASIC design to tie off unused outputs and 
    // explicitly declare bidirectional pins as inputs if unused.
    
    assign uio_out = 8'b00000000; // Tie output path to 0
    assign uio_oe  = 8'b00000000; // Set all bidirectional pins to Input mode

    // Suppress synthesis warnings for unused input signals.
    // This is a standard trick to tell the linter we are ignoring these on purpose.
    wire _unused = &{ena, ui_in, uio_in, 1'b0};

endmodule