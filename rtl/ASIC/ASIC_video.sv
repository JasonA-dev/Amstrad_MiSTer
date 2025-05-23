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
    input         asic_enabled,

    output asic_video_active,

    input [7:0] vram_dout,

    // Add outputs for DMA trigger
    output reg dma_hsync_pulse
);

// Internal registers for scanline and counters
reg [7:0] hsync_counter;
reg [7:0] hsync_after_vsync_counter;
reg [7:0] plus_irq_cause;
reg split_screen_event;

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
reg [3:0] r_reg;
reg [3:0] g_reg;
reg [3:0] b_reg;

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
wire        sprite_asic_ram_rd;
wire        sprite_asic_ram_wr;
wire [7:0]  sprite_asic_ram_din;

// Palette registers
reg [4:0] palette_pointer;   
reg [3:0] palette_latch_r;
reg [3:0] palette_latch_g;
reg [3:0] palette_latch_b;

// Selected palette
reg [11:0] selected_palette;

// Palette bank/effect support
reg [4:0] pal_idx;
reg [7:0] pal_data;
reg [13:0] pal_base;
reg [7:0] video_data;
reg [13:0] caddr;
reg [11:0] color12;

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

// Mode-specific timing control
reg [1:0] max_colour_ticks;  // Number of clock ticks per pixel
reg [1:0] ticks_increment;   // How much to increment the tick counter
reg [1:0] current_ticks;     // Current tick counter

// Mode lookup tables (simplified for now)
reg [7:0] mode0_lookup [0:15];  // Mode 0: 16 colors
reg [7:0] mode1_lookup [0:3];   // Mode 1: 4 colors
reg [7:0] mode2_lookup [0:1];   // Mode 2: 2 colors

// Decode video_config bits
wire alt_palette_en   = video_config[7]; // Alternate palette select
wire effect_en        = video_config[6]; // Effect enable
wire raster_effect_en = video_config[5]; // Raster effect enable
wire split_screen_cfg = video_config[4]; // Split screen config
wire palette_update_en= video_config[3]; // Palette update enable
wire palette_bank_sel = video_config[2]; // Palette bank select

// Remove duplicate mode lookup tables and keep the MAME-style ones
// --- MAME-style mode lookup tables ---
reg [3:0] mode_lookup_0 [0:255]; // Mode 0: 8bpp -> 16 colors
reg [1:0] mode_lookup_1 [0:255]; // Mode 1: 8bpp -> 4 colors
reg [0:0] mode_lookup_2 [0:255]; // Mode 2: 8bpp -> 2 colors

// Video update logic registers
reg [7:0] color_ticks;
reg [7:0] max_color_ticks;
reg [7:0] ticks;
reg [7:0] hscroll;
reg hsync_first_tick;
reg [7:0] hsync_tick_count;
reg [15:0] color;

// Palette fetch state machine states
localparam PF_IDLE      = 2'b00;
localparam PF_SET_ADDR  = 2'b01;
localparam PF_WAIT_DATA = 2'b10;
localparam PF_LATCH     = 2'b11;
reg [1:0] pf_state;
reg [13:0] pf_addr;
reg [7:0] pf_pal_idx;
reg [15:0] pf_color_latch;

// Add a reg to select the source of asic_ram_addr
reg asic_ram_addr_sel; // 0: palette fetch, 1: sprite

// Registers for DE edge logic
reg prev_crtc_de;
reg [13:0] de_ma_latch;
reg [4:0] de_ra_latch;

reg [7:0] h_start;
reg [7:0] h_end;
reg de_start;

reg [15:0] border_color;
reg [15:0] split_ma_base;
reg [15:0] split_ma_started;
reg sprite_update_req;

// Initialize mode lookup tables
initial begin
    for (integer i = 0; i < 256; i = i + 1) begin
        mode_lookup_0[i] = ((i & 8'h80) >> 7) | ((i & 8'h20) >> 3) | ((i & 8'h08) >> 2) | ((i & 8'h02) << 2);
        mode_lookup_1[i] = ((i & 8'h80) >> 7) | ((i & 8'h08) >> 2);
        mode_lookup_2[i] = ((i & 8'h80) >> 7);
    end
end

// Video mode handling
always @(posedge clk_sys) begin
    if (reset) begin
        max_color_ticks <= 8'h00;
        ticks_increment <= 8'h01;
        ticks <= 8'h00;
        color_ticks <= 8'h00;
        hscroll <= 8'h00;
        hsync_first_tick <= 1'b0;
        hsync_tick_count <= 8'h00;
        color <= 16'h0000;
        video_data <= 8'h00;
    end else if (cpu_wr && cpu_addr[15:8] == 8'hBC) begin
        if (cpu_addr[0] == 0) begin
            case (cpu_data[4:0])
                5'h01: begin
                    // Set mode-specific timing based on MRER[1:0]
                    case (cpu_data[1:0])
                        2'b00: begin  // Mode 0: 160x200, 16 colours
                            max_color_ticks <= 8'h03;  // 4 ticks
                            ticks_increment <= 8'h01;   // Increment by 1
                        end
                        2'b01: begin  // Mode 1: 320x200, 4 colours
                            max_color_ticks <= 8'h01;  // 2 ticks
                            ticks_increment <= 8'h01;   // Increment by 1
                        end
                        2'b10: begin  // Mode 2: 640x200, 2 colours
                            max_color_ticks <= 8'h00;  // 1 tick
                            ticks_increment <= 8'h01;   // Increment by 1
                        end
                        2'b11: begin  // Mode 3: 160x200, 4 colours
                            max_color_ticks <= 8'h03;  // 4 ticks
                            ticks_increment <= 8'h01;   // Increment by 1
                        end
                    endcase
                end
            endcase
        end
    end
end

// Video update logic
always @(posedge clk_sys) begin
    if (reset) begin
        color_ticks <= 8'h00;
        ticks <= 8'h00;
        hscroll <= 8'h00;
        hsync_first_tick <= 1'b0;
        hsync_tick_count <= 8'h00;
        color <= 16'h0000;
        video_data <= 8'h00;
    end else if (crtc_clken_actual) begin
        // HSync first tick detection
        if (crtc_hsync) begin
            hsync_tick_count <= hsync_tick_count + 1;
            if (hsync_tick_count > 16) begin
                hsync_first_tick <= 1'b0;
            end else begin
                hsync_first_tick <= 1'b1;
            end
        end else begin
            hsync_tick_count <= 8'h00;
        end

        if (!crtc_de) begin
            // During blanking, use border color
            color <= {asic_ram_q[7:0], asic_ram_q[15:8]}; // Little endian
        end else begin
            if (hscroll != 0) begin
                hscroll <= hscroll - 1;
                if (hscroll == 0) begin
                    // Get new video data when scroll completes
                    video_data <= vram_dout;
                end
            end else begin
                color_ticks <= color_ticks - 1;
                if (color_ticks == 0) begin
                    // Shift data and get new color
                    video_data <= {video_data[6:0], 1'b0};
                    // Palette fetch state machine will handle color fetch
                end
                
                ticks <= ticks + ticks_increment;
                case (ticks)
                    8'h08: begin
                        // Get new video data
                        video_data <= vram_dout;
                        // Palette fetch state machine will handle color fetch
                    end
                    8'h10: begin
                        // Increment memory address and get new video data
                        // crtc_ma <= crtc_ma + 1; // You cannot assign to input
                        video_data <= vram_dout;
                    end
                endcase
            end
        end
    end
end

// Palette fetch state machine
always @(posedge clk_sys) begin
    if (reset) begin
        pf_state <= PF_IDLE;
        pf_addr <= 14'h0000;
        pf_pal_idx <= 8'h00;
        pf_color_latch <= 16'h0000;
        color <= 16'h0000;
        asic_ram_addr_sel <= 1'b0;
    end else if (crtc_clken_actual) begin
        case (pf_state)
            PF_IDLE: begin
                if (crtc_de) begin
                    // Calculate palette index based on mode
                    case (mrer_mode[1:0])
                        2'b00: pf_pal_idx <= mode_lookup_0[video_data];
                        2'b01: pf_pal_idx <= mode_lookup_1[video_data];
                        2'b10: pf_pal_idx <= mode_lookup_2[video_data];
                        default: pf_pal_idx <= mode_lookup_0[video_data];
                    endcase
                    pf_addr <= 14'h2400 + pf_pal_idx * 2; // Palette base + index * 2
                    pf_state <= PF_SET_ADDR;
                end else begin
                    // Blanking: use border color (assume border at 0x2420)
                    pf_addr <= 14'h2420;
                    pf_state <= PF_SET_ADDR;
                end
            end
            PF_SET_ADDR: begin
                asic_ram_addr_sel <= 1'b0;
                pf_state <= PF_WAIT_DATA;
            end
            PF_WAIT_DATA: begin
                // Latch color low byte, set up for high byte
                pf_color_latch[7:0] <= asic_ram_q;
                asic_ram_addr_sel <= 1'b0;
                pf_state <= PF_LATCH;
            end
            PF_LATCH: begin
                // Latch color high byte
                pf_color_latch[15:8] <= asic_ram_q;
                color <= pf_color_latch;
                pf_state <= PF_IDLE;
            end
        endcase
    end
end

// Update color output based on fetched color and effects
always @(posedge clk_sys) begin
    if (reset) begin
        r_out <= 4'h0;
        g_out <= 4'h0;
        b_out <= 4'h0;
    end else if (crtc_clken_actual) begin
        if (crtc_de) begin
            if (effect_en) begin
                // Apply effects if enabled
                r_out <= ~color[11:8];
                g_out <= ~color[7:4];
                b_out <= ~color[3:0];
            end else if (plus_mode && asic_enabled) begin
                        case (asic_mode)
                            8'h02: begin
                        r_out <= color[11:8];
                        g_out <= color[7:4];
                        b_out <= color[3:0];
                            end
                            8'h62: begin
                                if (sprite_active_wire) begin
                            r_out <= color[11:8];
                            g_out <= color[7:4];
                            b_out <= color[3:0];
                                end else begin
                            r_out <= r_in;
                            g_out <= g_in;
                            b_out <= b_in;
                                end
                            end
                            8'h82: begin
                        r_out <= (color[11:8] + r_in) >> 1;
                        g_out <= (color[7:4] + g_in) >> 1;
                        b_out <= (color[3:0] + b_in) >> 1;
                            end
                            default: begin
                        r_out <= color[11:8];
                        g_out <= color[7:4];
                        b_out <= color[3:0];
                            end
                        endcase
                    end else begin
                r_out <= r_in;
                g_out <= g_in;
                b_out <= b_in;
                    end
        end else begin
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
    r_reg = 4'b0000;
    g_reg = 4'b0000;
    b_reg = 4'b0000;
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
    hsync_counter <= 0;
    hsync_after_vsync_counter <= 0;
    plus_irq_cause <= 0;
    split_screen_event <= 0;
    dma_hsync_pulse <= 0;
    prev_crtc_de <= 0;
    de_ma_latch <= 0;
    de_ra_latch <= 0;
    hsync_first_tick <= 0;
    hsync_tick_count <= 0;
    h_start <= 0;
    h_end <= 0;
    de_start <= 0;
    hscroll <= 0;
    border_color <= 0;
    split_ma_base <= 0;
    split_ma_started <= 0;
    sprite_update_req <= 0;
end

// CRTC and Gate Array register handling logic
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
        // Default - clear write signals
        crtc_reg_wr <= 1'b0;
        ga_reg_wr <= 1'b0;

        // Handle CRTC register writes (0xBCxx)
        if (cpu_wr && cpu_addr[15:8] == 8'hBC) begin
                    crtc_reg_wr <= 1'b1;
            crtc_reg_sel <= cpu_addr[3:0];  // Use lower bits for register select
                    crtc_reg_data <= cpu_data;
                end
                
        // Handle Gate Array register writes (0xBDxx)
        else if (cpu_wr && cpu_addr[15:8] == 8'hBD) begin
                    ga_reg_wr <= 1'b1;
            ga_reg_sel <= cpu_addr[3:0];  // Use lower bits for register select
                    ga_reg_data <= cpu_data;
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

assign asic_video_active = (asic_enabled && (asic_mode != 8'h00));

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

// In your palette fetch state machine and sprite logic, set asic_ram_addr_sel accordingly
// For example, when palette fetch is active, set asic_ram_addr_sel = 0; when sprite is active, set asic_ram_addr_sel = 1;

// Connect asic_ram_addr to the selected source
always @(*) begin
    if (asic_ram_addr_sel)
        asic_ram_addr = sprite_asic_ram_addr;
    else
        asic_ram_addr = pf_addr;
end

assign asic_ram_rd   = sprite_asic_ram_rd;
assign asic_ram_wr   = sprite_asic_ram_wr;
assign asic_ram_din  = sprite_asic_ram_din;

// HSYNC edge detection
reg prev_crtc_hsync;
always @(posedge clk_sys) begin
    if (reset) begin
        prev_crtc_hsync <= 1'b0;
    end else if (crtc_clken_actual) begin
        prev_crtc_hsync <= crtc_hsync;
    end
end

// Main HSYNC logic
always @(posedge clk_sys) begin
    if (reset) begin
        hsync_counter <= 0;
        hsync_after_vsync_counter <= 0;
        plus_irq_cause <= 0;
        split_screen_event <= 0;
        dma_hsync_pulse <= 0;
    end else if (crtc_clken_actual) begin
        dma_hsync_pulse <= 0; // default
        split_screen_event <= 0; // default
        // Detect falling edge of HSYNC
        if (prev_crtc_hsync && !crtc_hsync) begin
            // Advance to next drawing line
            hsync_counter <= hsync_counter + 1;
            // Reset line_ticks (not explicitly tracked)
            // Split screen event
            if (split_line != 0 && split_line == hsync_counter) begin
                split_screen_event <= 1;
                // Optionally: trigger split screen logic here
            end
            // PRI (Programmable Raster Interrupt)
            if (pri_line != 0 && pri_line == hsync_counter) begin
                pri_irq <= 1;
                plus_irq_cause <= 8'h06; // raster interrupt vector
            end
            // Raster interrupt timing
            if (hsync_after_vsync_counter != 0) begin
                hsync_after_vsync_counter <= hsync_after_vsync_counter - 1;
                if (hsync_after_vsync_counter == 1) begin // will become 0
                    if (hsync_counter >= 32) begin
                        if (pri_line == 0 || !asic_enabled) begin
                            pri_irq <= 1;
                        end
                    end
                    hsync_counter <= 0;
                end
            end
            if (hsync_counter >= 52) begin
                hsync_counter <= 0;
                if (pri_line == 0 || !asic_enabled) begin
                    pri_irq <= 1;
                end
            end
            // DMA trigger
            dma_hsync_pulse <= 1;
        end
        // VSYNC handling (reset hsync_counter at start of frame)
        if (crtc_vsync && !vsync_prev) begin
            hsync_counter <= 0;
            hsync_after_vsync_counter <= 0; // or set to initial value if needed
        end
    end
end

// DE edge detection and logic
always @(posedge clk_sys) begin
    if (reset) begin
        prev_crtc_de <= 0;
        de_ma_latch <= 0;
        de_ra_latch <= 0;
        hsync_first_tick <= 0;
        hsync_tick_count <= 0;
        h_start <= 0;
        h_end <= 0;
        de_start <= 0;
        hscroll <= 0;
        border_color <= 0;
        split_ma_base <= 0;
        split_ma_started <= 0;
        sprite_update_req <= 0;
    end else if (crtc_clken_actual) begin
        prev_crtc_de <= crtc_de;
        sprite_update_req <= 0; // default
        // Rising edge of DE
        if (!prev_crtc_de && crtc_de) begin
            // Latch MA/RA
            de_ma_latch <= crtc_ma;
            de_ra_latch <= crtc_ra;
            // Set hsync_first_tick and hsync_tick_count
            hsync_first_tick <= 1;
            hsync_tick_count <= 0;
            h_start <= 0; // You may want to use a pixel counter here
            // Handle de_start/hsync_counter
            if (de_start == 0) begin
                hsync_counter <= 0;
            end
            de_start <= 1;
            // Fetch border color from ASIC RAM (simulate fetch, use asic_ram_q if needed)
            border_color <= {asic_ram_q, asic_ram_q}; // Placeholder: real fetch needs sequencing
            // Fetch hscroll from ASIC RAM (simulate fetch, use asic_ram_q if needed)
            hscroll <= asic_ram_q & 8'h0F; // Placeholder: real fetch needs sequencing
            if (hscroll == 0) begin
                // Fetch new video data (handled elsewhere)
            end
            // Start of screen
            if (hsync_counter == 0) begin
                split_ma_base <= 16'h0000;
                split_ma_started <= 16'h0000;
            end
            // Start of split screen section
            else if (asic_enabled && asic_ram_q != 0 && asic_ram_q == hsync_counter - 1) begin
                split_ma_started <= de_ma_latch;
                split_ma_base <= {asic_ram_q, asic_ram_q}; // Placeholder: real fetch needs sequencing
            end
        end
        // Falling edge of DE
        if (prev_crtc_de && !crtc_de) begin
            h_end <= 0; // You may want to use a pixel counter here
            sprite_update_req <= 1; // Trigger sprite update
        end
    end
end

endmodule 