module GX4000_video
(
    input         clk_sys,
    input         reset,
    input         plus_mode,
    
    // CRTC Interface
    input         cclk_en_n,     // Add Gate Array clock enable
    input         crtc_clken,    // Keep for backward compatibility
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
    input   [1:0] r_in,
    input   [1:0] g_in,
    input   [1:0] b_in,
    
    // Video output
    output reg [3:0] r_out,
    output reg [3:0] g_out,
    output reg [3:0] b_out,
    
    // Sprite interface
    output wire        sprite_active_out,
    output wire  [3:0] sprite_id_out,
    output wire  [7:0] collision_reg,
    output reg        pri_irq,

    // ASIC RAM interface
    output [13:0] asic_ram_addr,
    output        asic_ram_rd,
    input   [7:0]  asic_ram_q,
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
    input         asic_enabled
);

// Internal signals
wire [7:0] collision_flags;
wire       sprite_active_wire;
wire [3:0] sprite_id_wire;

// Scroll control registers
reg [7:0] scroll_control;   
reg [7:0] scroll_control_sync;
reg [7:0] hscroll_count;    
reg [7:0] vscroll_count;    

// Split screen registers
reg [7:0] split_line;       
reg [15:0] split_addr;      

// Address calculation
reg [15:0] effective_addr;

// Priority control registers
reg [7:0] pri_line;         
reg [7:0] pri_control;      

// Priority counter
reg [7:0] pri_count;        

// Synchronized registers
reg [7:0] split_line_sync;
reg [15:0] split_addr_sync;
reg [7:0] pri_line_sync;
reg [7:0] pri_control_sync;

// Color registers
reg [1:0] r_reg;
reg [1:0] g_reg;
reg [1:0] b_reg;

// Configuration registers
reg [7:0] config_palette;
reg [7:0] config_sprite;
reg [7:0] config_video;
reg [7:0] config_io;

// Preset configuration
reg [7:0] config_preset;
reg [7:0] config_load [0:7][0:5];   

// Previous color values
reg [7:0] r_reg_prev;
reg [7:0] g_reg_prev;
reg [7:0] b_reg_prev;

// Frame counter
reg [7:0] frame_counter;

// Effect registers
reg [7:0] gray;
reg [7:0] wave_offset;
reg [7:0] wave_x;
reg [7:0] zoom_x;
reg [7:0] zoom_y;
reg [7:0] cycle_offset;

// Alpha blending
logic [7:0] alpha;

// Position registers
reg [8:0] pos_h;
reg [8:0] pos_v;

// Sprite ASIC RAM interface
wire [13:0] sprite_asic_ram_addr;

// Palette registers
reg [4:0] palette_pointer;   
reg [3:0] palette_latch_r;
reg [3:0] palette_latch_g;
reg [3:0] palette_latch_b;

// Selected palette
reg [11:0] selected_palette;

// Mode change registers
reg [7:0] new_video_mode;
reg [4:0] new_mrer_mode;

// Sync signal handling
reg sync_filter;
reg hsync_filtered;
reg vsync_filtered;
reg hblank_filtered;
reg vblank_filtered;

// ASIC sync signals
reg asic_hsync, asic_vsync, asic_hblank, asic_vblank;

// Use Gate Array clock enable for timing
wire crtc_clken_actual = cclk_en_n;

// Video output generation
always @(posedge clk_sys) begin
    if (reset) begin
        r_out <= 4'h0;
        g_out <= 4'h0;
        b_out <= 4'h0;
    end else if (cclk_en_n) begin
        if (crtc_de) begin
            case (config_mode)
                8'h00: begin
                    // Standard CPC mode - use Gate Array colors directly
                    r_out <= {2'b00, r_in};
                    g_out <= {2'b00, g_in};
                    b_out <= {2'b00, b_in};
                end
                default: begin
                    if (plus_mode && asic_enabled) begin
                        case (asic_mode)
                            8'h02: begin
                                // Mode 0x02: Standard Plus mode with palette
                                r_out <= palette_latch_r;
                                g_out <= palette_latch_g;
                                b_out <= palette_latch_b;
                            end
                            8'h62: begin
                                // Mode 0x62: Enhanced Plus mode with sprite priority
                                if (sprite_active_wire) begin
                                    r_out <= palette_latch_r;
                                    g_out <= palette_latch_g;
                                    b_out <= palette_latch_b;
                                end else begin
                                    r_out <= {2'b00, r_in};
                                    g_out <= {2'b00, g_in};
                                    b_out <= {2'b00, b_in};
                                end
                            end
                            8'h82: begin
                                // Mode 0x82: Advanced Plus mode with alpha blending
                                r_out <= (palette_latch_r + {2'b00, r_in}) >> 1;
                                g_out <= (palette_latch_g + {2'b00, g_in}) >> 1;
                                b_out <= (palette_latch_b + {2'b00, b_in}) >> 1;
                            end
                            default: begin
                                r_out <= palette_latch_r;
                                g_out <= palette_latch_g;
                                b_out <= palette_latch_b;
                            end
                        endcase
                    end else begin
                        // Non-Plus mode or ASIC not enabled: Direct 2-bit per channel
                        r_out <= {2'b00, r_in};
                        g_out <= {2'b00, g_in};
                        b_out <= {2'b00, b_in};
                    end
                end
            endcase
        end else begin
            // Blanking: Output black
            r_out <= 4'h0;
            g_out <= 4'h0;
            b_out <= 4'h0;
        end
    end
end

// Initialize registers
initial begin
    scroll_control = 8'h00;
    scroll_control_sync = 8'h00;
    hscroll_count = 8'h00;
    vscroll_count = 8'h00;
    split_line = 8'h00;
    split_addr = 16'h0000;
    effective_addr = 16'h0000;
    pri_line = 8'h00;
    pri_control = 8'h00;
    pri_count = 8'h00;
    split_line_sync = 8'h00;
    split_addr_sync = 16'h0000;
    pri_line_sync = 8'h00;
    pri_control_sync = 8'h00;
    r_reg = 2'b00;
    g_reg = 2'b00;
    b_reg = 2'b00;
    config_palette = 8'h00;
    config_sprite = 8'h00;
    config_video = 8'h00;
    config_io = 8'h00;
    config_preset = 8'h00;
    r_reg_prev = 8'h00;
    g_reg_prev = 8'h00;
    b_reg_prev = 8'h00;
    frame_counter = 8'h00;
    gray = 8'h00;
    wave_offset = 8'h00;
    wave_x = 8'h00;
    zoom_x = 8'h00;
    zoom_y = 8'h00;
    cycle_offset = 8'h00;
    alpha = 8'h00;
    pos_h = 9'h000;
    pos_v = 9'h000;
    palette_pointer = 5'h00;
    palette_latch_r = 4'h0;
    palette_latch_g = 4'h0;
    palette_latch_b = 4'h0;
    selected_palette = 12'h000;
    new_video_mode = 8'h00;
    new_mrer_mode = 5'h00;
    sync_filter = 1'b0;
    hsync_filtered = 1'b0;
    vsync_filtered = 1'b0;
    hblank_filtered = 1'b0;
    vblank_filtered = 1'b0;
    asic_hsync = 0;
    asic_vsync = 0;
    asic_hblank = 0;
    asic_vblank = 0;
end

// Register handling logic
always @(posedge clk_sys) begin
    if (reset) begin
        // Reset all ASIC registers
        crtc_reg_wr <= 1'b0;
        crtc_reg_sel <= 4'b0000;
        crtc_reg_data <= 8'h00;
        ga_reg_wr <= 1'b0;
        ga_reg_sel <= 4'b0000;
        ga_reg_data <= 8'h00;
    end else begin
        // Handle register writes
        if (cpu_wr && cpu_addr[15:8] == 8'h7F) begin
            case (cpu_addr[7:0])
                // ASIC Control Registers
                8'h00: begin
                    crtc_reg_wr <= 1'b1;
                    crtc_reg_sel <= 4'h0;
                    crtc_reg_data <= cpu_data;
                end
                8'h01: begin
                    crtc_reg_wr <= 1'b1;
                    crtc_reg_sel <= 4'h1;
                    crtc_reg_data <= cpu_data;
                end
                8'h02: begin
                    crtc_reg_wr <= 1'b1;
                    crtc_reg_sel <= 4'h2;
                    crtc_reg_data <= cpu_data;
                end
                
                // Video Control Registers
                8'h10: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h0;
                    ga_reg_data <= cpu_data;
                end
                8'h11: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h1;
                    ga_reg_data <= cpu_data;
                end
                8'h12: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h2;
                    ga_reg_data <= cpu_data;
                end
                8'h13: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h3;
                    ga_reg_data <= cpu_data;
                end
                8'h14: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h4;
                    ga_reg_data <= cpu_data;
                end
                
                // Sprite Control Registers
                8'h20: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h5;
                    ga_reg_data <= cpu_data;
                end
                8'h21: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h6;
                    ga_reg_data <= cpu_data;
                end
                8'h22: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h7;
                    ga_reg_data <= cpu_data;
                end
                8'h23: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h8;
                    ga_reg_data <= cpu_data;
                end
                8'h24: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'h9;
                    ga_reg_data <= cpu_data;
                end
                
                // Audio Control Registers
                8'h30: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'ha;
                    ga_reg_data <= cpu_data;
                end
                8'h31: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'hb;
                    ga_reg_data <= cpu_data;
                end
                8'h32: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'hc;
                    ga_reg_data <= cpu_data;
                end
                8'h33: begin
                    ga_reg_wr <= 1'b1;
                    ga_reg_sel <= 4'hd;
                    ga_reg_data <= cpu_data;
                end
            endcase
        end else begin
            crtc_reg_wr <= 1'b0;
            ga_reg_wr <= 1'b0;
        end
    end
end

// Palette handling
always @(posedge clk_sys) begin
    if (reset) begin
        palette_pointer <= 5'h00;
        palette_latch_r <= 4'h0;
        palette_latch_g <= 4'h0;
        palette_latch_b <= 4'h0;
    end else if (crtc_clken_actual) begin
        if (crtc_de) begin
            palette_pointer <= {crtc_ra[2:0], crtc_ma[1:0]};
        end

        // Only use ASIC palette if MRER[0] is set, as on real hardware
        if (plus_mode && asic_enabled && mrer_mode[0]) begin
            case (asic_mode)
                8'h02, 8'h62, 8'h82: begin
                    palette_latch_r <= {2'b00, asic_ram_q[1:0]};
                    palette_latch_g <= {2'b00, asic_ram_q[3:2]};
                    palette_latch_b <= {2'b00, asic_ram_q[5:4]};
                end
                default: begin
                    palette_latch_r <= {2'b00, r_in};
                    palette_latch_g <= {2'b00, g_in};
                    palette_latch_b <= {2'b00, b_in};
                end
            endcase
        end else begin
            palette_latch_r <= {2'b00, r_in};
            palette_latch_g <= {2'b00, g_in};
            palette_latch_b <= {2'b00, b_in};
        end
    end
end

// Sprite instance
GX4000_sprite sprite_inst (
    .clk_sys(clk_sys),
    .reset(reset),
    .plus_mode(plus_mode),
    
    // CPU interface
    .cpu_addr(cpu_addr),
    .cpu_data(cpu_data),
    .cpu_wr(cpu_wr),
    .cpu_rd(cpu_rd),
    
    // Video interface
    .hpos(hpos),
    .vpos(vpos),
    .hblank(hblank),
    .vblank(vblank),
    
    // Sprite output
    .sprite_active(sprite_active_wire),
    .sprite_id(sprite_id_wire),
    
    // Configuration
    .config_sprite(sprite_config),
    .collision_flags(collision_flags),
    
    // ASIC RAM interface
    .asic_ram_addr(sprite_asic_ram_addr),
    .asic_ram_rd(sprite_asic_ram_rd),
    .asic_ram_q(asic_ram_q),
    .asic_ram_wr(sprite_asic_ram_wr),
    .asic_ram_din(sprite_asic_ram_din)
);

// Connect sprite outputs
assign sprite_active_out = sprite_active_wire;
assign sprite_id_out = sprite_id_wire;
assign collision_reg = collision_flags;

// Priority interrupt generation
always @(posedge clk_sys) begin
    if (reset) begin
        pri_irq <= 1'b0;
        pri_count <= 8'h00;
    end else if (crtc_clken_actual) begin
        if (crtc_de && pri_control[0]) begin
            if (pri_count == pri_line) begin
                pri_irq <= 1'b1;
            end
            pri_count <= pri_count + 1;
        end else begin
            pri_irq <= 1'b0;
            pri_count <= 8'h00;
        end
    end
end

// Use real ASIC sync signal inputs
always @(posedge clk_sys) begin
    if (reset) begin
        asic_hsync  <= 0;
        asic_vsync  <= 0;
        asic_hblank <= 0;
        asic_vblank <= 0;
    end else if (crtc_clken_actual) begin
        asic_hsync  <= asic_hsync_in;
        asic_vsync  <= asic_vsync_in;
        asic_hblank <= asic_hblank_in;
        asic_vblank <= asic_vblank_in;
    end
end

// Sync signal generation
always @(posedge clk_sys) begin
    if (reset) begin
        sync_filter <= 1'b0;
        hsync_filtered <= 1'b0;
        vsync_filtered <= 1'b0;
        hblank_filtered <= 1'b0;
        vblank_filtered <= 1'b0;
    end else if (crtc_clken_actual) begin
        if (asic_enabled) begin
            // Plus mode: Use ASIC sync timing
            sync_filter    <= 1'b1;
            hsync_filtered <= asic_hsync;
            vsync_filtered <= asic_vsync;
            hblank_filtered <= asic_hblank;
            vblank_filtered <= asic_vblank;
        end else begin
            // Non-Plus mode: Use CRTC sync timing
            sync_filter    <= 1'b0;
            hsync_filtered <= crtc_hsync;
            vsync_filtered <= crtc_vsync;
            hblank_filtered <= ~crtc_de;
            vblank_filtered <= (crtc_ra == 5'h00);
        end
    end
end

// Frame counter
reg vsync_prev;
always @(posedge clk_sys) begin
    if (reset) begin
        frame_counter <= 8'h00;
        vsync_prev <= 1'b0;
    end else begin
        vsync_prev <= crtc_vsync;
        if (crtc_vsync && !vsync_prev) begin
            frame_counter <= frame_counter + 1;
        end
    end
end

// Local parameters
localparam SPRITE_ATTR_BASE = 14'h0000;    // Sprite attributes start at 0x0000
localparam SPRITE_PATTERN_BASE = 14'h0200;  // Sprite patterns start at 0x0200
localparam SPRITE_ATTR_SIZE = 14'h0020;     // 32 bytes for 16 sprites
localparam SPRITE_PATTERN_SIZE = 14'h0100;  // 256 bytes per sprite pattern

assign asic_ram_addr = sprite_asic_ram_addr;
assign asic_ram_rd   = sprite_asic_ram_rd;
assign asic_ram_wr   = sprite_asic_ram_wr;
assign asic_ram_din  = sprite_asic_ram_din;

endmodule 