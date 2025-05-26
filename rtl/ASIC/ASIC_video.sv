module GX4000_video
(
    input         clk_sys,
    input         reset,
    input         plus_mode,
    
    // CRTC Interface
    input         cclk_en_n,    
    input         crtc_clken,   
    input         crtc_nclken,
    input  [13:0] crtc_ma,
    input   [4:0] crtc_ra,
    input         crtc_de,
    input         crtc_field,
    input         crtc_cursor,
    input         crtc_vsync,
    input         crtc_hsync,
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data,
    input         cpu_wr,
    input         cpu_rd,
    
    // Video interface
    input   [8:0] hpos,
    input   [8:0] vpos,
    input         hblank,
    input         vblank,
    input   [3:0] r_in,
    input   [3:0] g_in,
    input   [3:0] b_in,
    
    // Video output
    output reg [3:0] r_out,
    output reg [3:0] g_out,
    output reg [3:0] b_out,
    
    // Sprite interface
    output wire        sprite_active_out,
    output wire  [3:0] sprite_id_out,
    output wire  [7:0] collision_reg,

    // ASIC RAM interface
    output [13:0] asic_ram_addr,
    output        asic_ram_rd,
    input   [7:0] asic_ram_q,
    output        asic_ram_wr,
    output [7:0]  asic_ram_din,

    // CRTC update interface
    output reg        crtc_reg_wr,
    output reg  [3:0] crtc_reg_sel,
    output reg  [7:0] crtc_reg_data,

    // GA40010 (Gate Array) update interface
    output reg        ga_reg_wr,
    output reg  [3:0] ga_reg_sel,
    output reg  [7:0] ga_reg_data,

    // Real ASIC sync signal inputs
    input             asic_hsync_in,
    input             asic_vsync_in,
    input             asic_hblank_in,
    input             asic_vblank_in,

    // Register interface
    input [7:0]      asic_control,
    input [7:0]      asic_status,
    input [7:0]      asic_config,
    input [7:0]      video_control,
    input [7:0]      video_status,
    input [7:0]      video_config,
    input [7:0]      video_palette,
    input [7:0]      video_effect,
    input [7:0]      sprite_control,
    input [7:0]      sprite_status,
    input [7:0]      sprite_config,
    input [7:0]      sprite_priority,
    input [7:0]      sprite_collision,

    // Video mode inputs
    input   [7:0] config_mode,
    input   [4:0] mrer_mode,
    input   [7:0] asic_mode,
    input         asic_enabled,

    output asic_video_active,

    input [7:0] vram_dout,

    // Add outputs for DMA trigger
    output reg dma_hsync_pulse,

    // Expose current raster line for PRI
    output reg [7:0] raster_line
);

// Assign unused outputs
assign sprite_active_out = 1'b0;
assign sprite_id_out = 4'b0;
assign collision_reg = 8'b0;
assign asic_ram_addr = 14'b0;
assign asic_ram_rd = 1'b0;
assign asic_ram_wr = 1'b0;
assign asic_ram_din = 8'b0;
assign asic_video_active = 1'b1;

wire extended_colours = 1'b1;
// GA (CPC) palette (from color_mix)
reg [23:0] ga_palette [0:26];
// ASIC (Plus) palette (from color_mix)
reg [23:0] asic_palette [0:26];
initial begin
    // GA palette
    ga_palette[ 0] = 24'h000201;
    ga_palette[ 1] = 24'h00026B;
    ga_palette[ 2] = 24'h0C02F4;
    ga_palette[ 3] = 24'h6C0201;
    ga_palette[ 4] = 24'h690268;
    ga_palette[ 5] = 24'h6C02F2;
    ga_palette[ 6] = 24'hF30506;
    ga_palette[ 7] = 24'hF00268;
    ga_palette[ 8] = 24'hF302F4;
    ga_palette[ 9] = 24'h027801;
    ga_palette[10] = 24'h007868;
    ga_palette[11] = 24'h0C7BF4;
    ga_palette[12] = 24'h6E7B01;
    ga_palette[13] = 24'h6E7D6B;
    ga_palette[14] = 24'h6E7BF6;
    ga_palette[15] = 24'hF37D0D;
    ga_palette[16] = 24'hF37D6B;
    ga_palette[17] = 24'hFA80F9;
    ga_palette[18] = 24'h02F001;
    ga_palette[19] = 24'h00F36B;
    ga_palette[20] = 24'h0FF3F2;
    ga_palette[21] = 24'h71F504;
    ga_palette[22] = 24'h71F36B;
    ga_palette[23] = 24'h71F3F4;
    ga_palette[24] = 24'hF3F30D;
    ga_palette[25] = 24'hF3F36D;
    ga_palette[26] = 24'hFFF3F9;
    // ASIC palette
    asic_palette[ 0] = 24'h020702;
    asic_palette[ 1] = 24'h050663;
    asic_palette[ 2] = 24'h0507f1;
    asic_palette[ 3] = 24'h670600;
    asic_palette[ 4] = 24'h680764;
    asic_palette[ 5] = 24'h6807F1;
    asic_palette[ 6] = 24'hFD0704;
    asic_palette[ 7] = 24'hFF0764;
    asic_palette[ 8] = 24'hFD07F2;
    asic_palette[ 9] = 24'h046703;
    asic_palette[10] = 24'h046764;
    asic_palette[11] = 24'h0567F1;
    asic_palette[12] = 24'h686704;
    asic_palette[13] = 24'h686764;
    asic_palette[14] = 24'h6867F1;
    asic_palette[15] = 24'hFD6704;
    asic_palette[16] = 24'hFD6763;
    asic_palette[17] = 24'hFD67F1;
    asic_palette[18] = 24'h04F502;
    asic_palette[19] = 24'h04F562;
    asic_palette[20] = 24'h04F5F1;
    asic_palette[21] = 24'h68F500;
    asic_palette[22] = 24'h68F564;
    asic_palette[23] = 24'h68F5F1;
    asic_palette[24] = 24'hFEF504;
    asic_palette[25] = 24'hFDF563;
    asic_palette[26] = 24'hFDF5F0;
end

// Single pixel counter for 4096-color sweep
reg [11:0] pixel_counter;
reg crtc_hsync_d, crtc_vsync_d;

wire test_pattern = 1'b0;
wire test_color_sweep = 1'b0; // set to 0 for palette test, 1 for 4096 sweep

always @(posedge clk_sys) begin
    if (reset) begin
        pixel_counter <= 0;
        crtc_hsync_d <= 0;
        crtc_vsync_d <= 0;
    end else begin
        crtc_hsync_d <= crtc_hsync;
        crtc_vsync_d <= crtc_vsync;
        pixel_counter <= pixel_counter + 1;
        
        if (crtc_vsync_d && !crtc_vsync) begin
            pixel_counter <= 0;
        end
    end
end

wire [4:0]  pal_idx = pixel_counter % 27;
wire [23:0] pal_rgb = asic_palette[pal_idx];

always @* begin
    if (plus_mode) begin
        if(test_pattern) begin
            if (test_color_sweep) begin
                // 4096-color sweep
                r_out = pixel_counter[11:8];
                g_out = pixel_counter[7:4];
                b_out = pixel_counter[3:0];
            end else begin
                // ASIC palette test
                r_out = pal_rgb[23:16];
                g_out = pal_rgb[15:8];
                b_out = pal_rgb[7:0];
            end
        end else begin
            r_out = r_in;
            g_out = g_in;
            b_out = b_in;
        end
    end else begin
        r_out = 4'h0;
        g_out = 4'h0;
        b_out = 4'hF;
    end
end

endmodule 