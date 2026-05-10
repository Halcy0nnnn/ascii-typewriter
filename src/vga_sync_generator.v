`default_nettype none

module vga_sync_generator (
    input  wire       clk,          // 25 MHz clock
    input  wire       rst_n,        // Active-low reset
    output reg  [9:0] h_count,      // Current horizontal pixel (0-799)
    output reg  [9:0] v_count,      // Current vertical line (0-524)
    output wire       hsync,        // Horizontal sync (active low)
    output wire       vsync,        // Vertical sync (active low)
    output wire       video_active  // High when in the visible screen area
);

    // --------------------------------------------------------
    // VGA 640x480 @ 60Hz Timing Parameters
    // --------------------------------------------------------
    // Horizontal timing (pixels)
    localparam H_DISPLAY       = 640;
    localparam H_FRONT_PORCH   = 16;
    localparam H_SYNC_PULSE    = 96;
    localparam H_BACK_PORCH    = 48;
    localparam H_TOTAL         = H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE + H_BACK_PORCH; // 800

    // Vertical timing (lines)
    localparam V_DISPLAY       = 480;
    localparam V_FRONT_PORCH   = 10;
    localparam V_SYNC_PULSE    = 2;
    localparam V_BACK_PORCH    = 33;
    localparam V_TOTAL         = V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE + V_BACK_PORCH; // 525

    // --------------------------------------------------------
    // Counters
    // --------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'd0;
                if (v_count == V_TOTAL - 1) begin
                    v_count <= 10'd0;
                end else begin
                    v_count <= v_count + 10'd1;
                end
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // --------------------------------------------------------
    // Sync and Blanking Generation
    // --------------------------------------------------------
    // HSYNC and VSYNC are active low for 640x480 resolution
    assign hsync = ~((h_count >= H_DISPLAY + H_FRONT_PORCH) && 
                     (h_count <  H_DISPLAY + H_FRONT_PORCH + H_SYNC_PULSE));
                     
    assign vsync = ~((v_count >= V_DISPLAY + V_FRONT_PORCH) && 
                     (v_count <  V_DISPLAY + V_FRONT_PORCH + V_SYNC_PULSE));

    // video_active is high only during the display phase
    assign video_active = (h_count < H_DISPLAY) && (v_count < V_DISPLAY);

endmodule