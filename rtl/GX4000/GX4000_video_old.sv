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
    output reg        sprite_active_out,
    output reg  [3:0] sprite_id_out,
    output reg  [7:0] collision_reg,
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
    input             asic_vblank_in
);

// ASIC Control Registers (0x7F00-0x7F0F)
reg [7:0] asic_control;      // 0x7F00: ASIC Control Register
reg [7:0] asic_status;       // 0x7F01: ASIC Status Register
reg [7:0] asic_config;       // 0x7F02: ASIC Configuration Register
reg [7:0] asic_version;      // 0x7F03: ASIC Version Register

// Video Control Registers (0x7F10-0x7F1F)
reg [7:0] video_control;     // 0x7F10: Video Mode Control
reg [7:0] video_status;      // 0x7F11: Video Status
reg [7:0] video_config;      // 0x7F12: Video Configuration
reg [7:0] video_palette;     // 0x7F13: Video Palette Control
reg [7:0] video_effect;      // 0x7F14: Video Effect Control

// Sprite Control Registers (0x7F20-0x7F2F)
reg [7:0] sprite_control;    // 0x7F20: Sprite Control
reg [7:0] sprite_status;     // 0x7F21: Sprite Status
reg [7:0] sprite_config;     // 0x7F22: Sprite Configuration
reg [7:0] sprite_priority;   // 0x7F23: Sprite Priority Control
reg [7:0] sprite_collision;  // 0x7F24: Sprite Collision Status

// Audio Control Registers (0x7F30-0x7F3F)
reg [7:0] audio_control;     // 0x7F30: Audio Control
reg [7:0] audio_status;      // 0x7F31: Audio Status
reg [7:0] audio_config;      // 0x7F32: Audio Configuration
reg [7:0] audio_volume;      // 0x7F33: Audio Volume Control

// Add at the top of the module:
reg [13:0] asic_ram_addr_reg;
reg        asic_ram_rd_reg;
reg        asic_ram_wr_reg;
reg [7:0]  asic_ram_din_reg;

    // Internal signals
    wire [7:0] collision_flags;
    reg        sprite_active;
    reg [3:0]  sprite_id;
    wire       sprite_active_wire;
    
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
    
    // Mode registers
    reg [4:0] mrer_mode;       
    reg [7:0] asic_mode;      // New register for ASIC mode control
    reg       asic_enabled;    // Flag to indicate if ASIC is taking over video
    
    // Color registers
    reg [1:0] r_reg;
    reg [1:0] g_reg;
    reg [1:0] b_reg;
    
    // Configuration registers
    reg [7:0] config_mode;
    reg [7:0] config_palette;
    reg [7:0] config_sprite;
    reg [7:0] config_video;
    reg [7:0] config_audio;
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


// ------------------------------------------------------------------------------------------------
// ASIC mode handling
// ------------------------------------------------------------------------------------------------
    reg [1:0] video_mode;
    always @(posedge clk_sys) begin
        if (reset) begin
            video_mode <= 2'b00;
        end else if (cpu_wr && cpu_addr[15:8] == 8'hBC) begin
            if (cpu_addr[0] == 0) begin
                    case (cpu_data[4:0])
                    5'h00: video_mode <= cpu_data[1:0];
                    endcase
            end
        end
    end

    // Use Gate Array clock enable for timing
    wire crtc_clken_actual = cclk_en_n;


// ------------------------------------------------------------------------------------------------
// Video output generation
// ------------------------------------------------------------------------------------------------
    always @(posedge clk_sys) begin
        if (reset) begin
            r_out <= 4'h0;
            g_out <= 4'h0;
            b_out <= 4'h0;
        end else if (cclk_en_n) begin
        if (crtc_de) begin
            /*
            if (plus_mode && asic_enabled && asic_ram_rd) begin
                    r_out <= palette_latch_r;
                    g_out <= palette_latch_g;
                    b_out <= palette_latch_b;
                    $display("ASIC mode: r_out=%h, g_out=%h, b_out=%h", palette_latch_r, palette_latch_g, palette_latch_b);
            end else begin
                    // Non-Plus mode or ASIC not reading: Direct 2-bit per channel from motherboard Gate Array
                    // No palette lookup, just expand 2-bit to 4-bit
                    r_out <= {2'b00, r_in};
                    g_out <= {2'b00, g_in};
                    b_out <= {2'b00, b_in};
                    $display("Motherboard mode: r_in=%b, g_in=%b, b_in=%b, r_out=%h, g_out=%h, b_out=%h", 
                            r_in, g_in, b_in, {2'b00, r_in}, {2'b00, g_in}, {2'b00, b_in});
            end
*/

            // ------------------------------------------------------------------------------------------------
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
                                if (sprite_active) begin
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
            // ------------------------------------------------------------------------------------------------


        end else begin
            // Blanking: Output black
            r_out <= 4'h0;
            g_out <= 4'h0;
            b_out <= 4'h0;
        end
    end
end
            
// ------------------------------------------------------------------------------------------------
// Initialize registers
// ------------------------------------------------------------------------------------------------
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
        mrer_mode = 5'h00;
        asic_mode = 8'h00;
        asic_enabled = 1'b0;
        r_reg = 2'b00;
        g_reg = 2'b00;
        b_reg = 2'b00;
        config_mode = 8'h00;
        config_palette = 8'h00;
        config_sprite = 8'h00;
        config_video = 8'h00;
        config_audio = 8'h00;
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

        // ASIC Control Registers
    asic_control = 8'h00;
    asic_status = 8'h00;
    asic_config = 8'h00;
    asic_version = 8'h01;  // Version 1.0

    // Video Control Registers
    video_control = 8'h00;
    video_status = 8'h00;
    video_config = 8'h00;
    video_palette = 8'h00;
    video_effect = 8'h00;

    // Sprite Control Registers
    sprite_control = 8'h00;
    sprite_status = 8'h00;
    sprite_config = 8'h00;
    sprite_priority = 8'h00;
    sprite_collision = 8'h00;

    // Audio Control Registers
    audio_control = 8'h00;
    audio_status = 8'h00;
    audio_config = 8'h00;
    audio_volume = 8'h7F;  // Default volume    
    end

// ------------------------------------------------------------------------------------------------
// ASIC register handling for 0x7F00-0x7FFF range
// ------------------------------------------------------------------------------------------------
always @(posedge clk_sys) begin
    if (reset) begin
        // Reset all ASIC registers
        asic_control <= 8'h00;
        asic_status <= 8'h00;
        asic_config <= 8'h00;
        video_control <= 8'h00;
        video_status <= 8'h00;
        video_config <= 8'h00;
        video_palette <= 8'h00;
        video_effect <= 8'h00;
        sprite_control <= 8'h00;
        sprite_status <= 8'h00;
        sprite_config <= 8'h00;
        sprite_priority <= 8'h00;
        sprite_collision <= 8'h00;
        audio_control <= 8'h00;
        audio_status <= 8'h00;
        audio_config <= 8'h00;
        audio_volume <= 8'h7F;
    end else begin
        // Handle register writes
        if (cpu_wr && cpu_addr[15:8] == 8'h7F) begin
            case (cpu_addr[7:0])
                // ASIC Control Registers
                8'h00: begin
                    asic_control <= cpu_data;
                    video_control <= cpu_data;  // Directly update video control
                end
                8'h01: asic_status <= cpu_data;
                8'h02: begin
                    asic_config <= cpu_data;
                    video_config <= cpu_data;  // Directly update video config
                end
                
                // Video Control Registers
                8'h10: video_control <= cpu_data;
                8'h11: video_status <= cpu_data;
                8'h12: video_config <= cpu_data;
                8'h13: video_palette <= cpu_data;
                8'h14: video_effect <= cpu_data;
                
                // Sprite Control Registers
                8'h20: sprite_control <= cpu_data;
                8'h21: sprite_status <= cpu_data;
                8'h22: sprite_config <= cpu_data;
                8'h23: sprite_priority <= cpu_data;
                8'h24: sprite_collision <= cpu_data;
                
                // Audio Control Registers
                8'h30: audio_control <= cpu_data;
                8'h31: audio_status <= cpu_data;
                8'h32: audio_config <= cpu_data;
                8'h33: audio_volume <= cpu_data;
            endcase
        end

        // Update status registers
        asic_status[0] <= asic_enabled;  // ASIC enabled bit
        asic_status[1] <= plus_mode;     // Plus mode bit
        asic_status[2] <= sync_filter;   // Sync filter status
        asic_status[3] <= pri_irq;       // Priority interrupt status
        asic_status[4] <= sprite_active; // Sprite active status
        asic_status[5] <= |collision_flags; // Collision status
        asic_status[6] <= crtc_de;       // Display enable status
        asic_status[7] <= crtc_vsync;    // Vertical sync status

        // Mirror to video status
        video_status <= asic_status;

        // Update sprite status
        sprite_status[0] <= sprite_active; // Sprite active
        sprite_status[1] <= |collision_flags; // Collision detected
        sprite_status[2] <= sprite_priority[0]; // Priority status
        sprite_status[3] <= asic_enabled; // ASIC enabled
        sprite_status[4] <= plus_mode;    // Plus mode
        sprite_status[5] <= crtc_de;      // Display enable
        sprite_status[6] <= crtc_vsync;   // Vertical sync
        sprite_status[7] <= crtc_hsync;   // Horizontal sync

        // Update audio status
        audio_status[0] <= asic_enabled;  // ASIC enabled
        audio_status[1] <= plus_mode;     // Plus mode
        audio_status[2] <= crtc_de;       // Display enable
        audio_status[3] <= crtc_vsync;    // Vertical sync
        audio_status[4] <= crtc_hsync;    // Horizontal sync
        audio_status[5] <= sprite_active; // Sprite active
        audio_status[6] <= |collision_flags; // Collision detected
        audio_status[7] <= pri_irq;       // Priority interrupt
    end
end

// ------------------------------------------------------------------------------------------------
// ASIC register read handling
// ------------------------------------------------------------------------------------------------

// Add new synchronized register set
reg [7:0] asic_control_sync;
reg [7:0] asic_status_sync;
reg [7:0] asic_config_sync;
reg [7:0] video_control_sync;
reg [7:0] video_status_sync;
reg [7:0] video_config_sync;

// Synchronize registers with CRTC timing
always @(posedge clk_sys) begin
    if (reset) begin
        asic_control_sync <= 8'h00;
        asic_status_sync <= 8'h00;
        asic_config_sync <= 8'h00;
        video_control_sync <= 8'h00;
        video_status_sync <= 8'h00;
        video_config_sync <= 8'h00;
    end else if (crtc_clken_actual) begin
        // Only update synchronized registers during active display
        if (crtc_de) begin
            asic_control_sync <= asic_control;
            asic_status_sync <= asic_status;
            asic_config_sync <= asic_config;
            video_control_sync <= video_control;
            video_status_sync <= video_status;
            video_config_sync <= video_config;
        end
    end
end

// ------------------------------------------------------------------------------------------------
// CRTC synchronization
// ------------------------------------------------------------------------------------------------
    always @(posedge clk_sys) begin
        if (reset) begin
            scroll_control_sync <= 8'h00;
            split_line_sync <= 8'h00;
            split_addr_sync <= 16'h0000;
            pri_line_sync <= 8'h00;
            pri_control_sync <= 8'h00;
        end else if (crtc_clken_actual) begin
            scroll_control_sync <= scroll_control;
            split_line_sync <= split_line;
            split_addr_sync <= split_addr;
            pri_line_sync <= pri_line;
            pri_control_sync <= pri_control;
        end
    end

// ------------------------------------------------------------------------------------------------
// Video mode handling
// ------------------------------------------------------------------------------------------------
    always @(posedge clk_sys) begin
        if (reset) begin
            config_mode <= 8'h00;
            mrer_mode <= 5'h00;
            asic_mode <= 8'h00;
            asic_enabled <= 1'b0;
        end else if (cpu_wr && cpu_addr[15:8] == 8'hBC) begin
            if (cpu_addr[0] == 0) begin
                case (cpu_data[4:0])
                    5'h00: begin
                        config_mode <= cpu_data;
                        //$display("Config mode set to %h", cpu_data);
                    end
                    5'h01: begin
                        mrer_mode <= cpu_data[4:0];
                        //$display("MRER mode set to %h", cpu_data[4:0]);
                    end
                    5'h02: begin
                        asic_mode <= cpu_data;
                        // Enable ASIC in Plus mode for modes 0x02, 0x62, and 0x82
                        asic_enabled <= ((cpu_data == 8'h02) || (cpu_data == 8'h62) || (cpu_data == 8'h82)) && plus_mode;
                        //$display("ASIC mode set to %h, enabled=%b, plus_mode=%b", 
                        //        cpu_data, asic_enabled, plus_mode);
                    end
                endcase
            end
        end
    end


// ------------------------------------------------------------------------------------------------
// Palette handling
// ------------------------------------------------------------------------------------------------
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

        // Always update palette latches for every pixel, not just when crtc_de is high
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

// ------------------------------------------------------------------------------------------------
// Sprite handling
// ------------------------------------------------------------------------------------------------
    always @(posedge clk_sys) begin
        if (reset) begin
            sprite_active <= 1'b0;
            sprite_id <= 4'h0;
            sprite_active_out <= 1'b0;
            sprite_id_out <= 4'h0;
            collision_reg <= 8'h00;
        end else if (crtc_clken_actual) begin
            if (crtc_de) begin
                // Check for sprite collision and update status
                sprite_active <= (crtc_ma[13:10] == 4'hF);
                sprite_id <= crtc_ma[9:6];
                sprite_active_out <= sprite_active;
                sprite_id_out <= sprite_id;
                collision_reg <= collision_flags;
            end else begin
                sprite_active <= 1'b0;
                sprite_id <= 4'h0;
                sprite_active_out <= 1'b0;
                sprite_id_out <= 4'h0;
            end
        end
    end



// ------------------------------------------------------------------------------------------------
// Priority interrupt generation
// ------------------------------------------------------------------------------------------------
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


    // ASIC RAM control signals
    wire asic_ram_rd_en;
    wire asic_ram_wr_en;
    wire sprite_asic_ram_rd;
    wire sprite_asic_ram_wr;
    
    // Assign sprite_active_wire to sprite_active for use in continuous assignments
    assign sprite_active_wire = sprite_active;
    
    // ASIC RAM control logic
    assign asic_ram_rd_en = crtc_clken_actual && asic_enabled;  // Only enable reads when ASIC is enabled
    assign asic_ram_wr_en = asic_enabled && 
        (cpu_wr && (cpu_addr[15:8] == 8'h60) && (cpu_addr[7:5] < 4'h2) || 
         cpu_wr && (cpu_addr[15:8] == 8'h40) || 
         (cpu_wr && (cpu_addr[15:8] == 8'hBC)));
   /* 
// Debug output for CRTC timing
always @(posedge clk_sys) begin
    if (crtc_clken_actual && crtc_vsync) begin
       $display("[VIDEO_TIMING] ma=%h, ra=%h, de=%b, vsync=%b, hsync=%b",
               crtc_ma, crtc_ra, crtc_de, crtc_vsync, crtc_hsync);
    end
end
*/
    // Debug output for ASIC RAM read conditions
    always @(posedge clk_sys) begin
        if (crtc_clken_actual) begin
            if (crtc_de) begin
                /*
                $display("[VIDEO_DEBUG] ASIC RAM read conditions: crtc_clken=%b, crtc_de=%b, asic_enabled=%b, plus_mode=%b, ma=%h, ra=%h", 
                        crtc_clken_actual, crtc_de, asic_enabled, plus_mode, crtc_ma, crtc_ra);
                $display("[VIDEO_DEBUG] ASIC mode=%h, asic_ram_rd=%b, asic_ram_addr=%h", 
                        asic_mode, asic_ram_rd, asic_ram_addr);
                $display("[VIDEO_DEBUG] Video output: r_out=%h, g_out=%h, b_out=%h", 
                        r_out, g_out, b_out);
                $display("[VIDEO_DEBUG] ASIC RAM data: q=%h", asic_ram_q);
                */
            end
        end
    end

/*
    // Debug output for palette access
    always @(posedge clk_sys) begin
        if (crtc_clken_actual && plus_mode) begin
            $display("[VIDEO_DEBUG] Palette access: pointer=%h, addr=%h, data=%h", 
                    palette_pointer, asic_ram_addr, asic_ram_q);
            //$display("[VIDEO_DEBUG] Palette colors: r=%h, g=%h, b=%h", 
            //        palette_latch_r, palette_latch_g, palette_latch_b);
            //$display("[VIDEO_DEBUG] Input colors: r_in=%b, g_in=%b, b_in=%b", 
            //        r_in, g_in, b_in);
        end
    end
*/
/*
    // Debug output for mode changes
    always @(posedge clk_sys) begin
        if (cpu_wr && cpu_addr[15:8] == 8'hBC) begin
            if (cpu_addr[0] == 0) begin
                case (cpu_data[4:0])
                    5'h00: $display("[VIDEO_DEBUG] Config mode changed to %h", cpu_data);
                    5'h01: $display("[VIDEO_DEBUG] MRER mode changed to %h", cpu_data[4:0]);
                    5'h02: begin
                        $display("[VIDEO_DEBUG] ASIC mode changed to %h, plus_mode=%b", cpu_data, plus_mode);
                        $display("[VIDEO_DEBUG] ASIC enabled will be: %b", ((cpu_data == 8'h02) || (cpu_data == 8'h62) || (cpu_data == 8'h82)) && plus_mode);
                        $display("[VIDEO_DEBUG] Current ASIC state: mode=%h, enabled=%b", asic_mode, asic_enabled);
                    end
                endcase
            end
        end
    end
*/
    // Sprite ASIC RAM control logic
    assign sprite_asic_ram_rd = asic_ram_rd_en && sprite_active_wire;
    assign sprite_asic_ram_wr = asic_ram_wr_en && sprite_active_wire;
    
    // ASIC RAM interface
    wire is_sprite_attr_write = cpu_wr && (cpu_addr[15:8] == 8'h60) && (cpu_addr[7:5] < 4'h2);
    wire is_sprite_pattern_write = cpu_wr && (cpu_addr[15:8] == 8'h40);

    assign asic_ram_addr = asic_enabled ? 
        (sprite_active_wire ? 
            (sprite_asic_ram_addr[13:8] == 6'h00 ? 
                SPRITE_ATTR_BASE + sprite_asic_ram_addr[4:0] :  // Attribute access
                SPRITE_PATTERN_BASE + sprite_asic_ram_addr[13:0]  // Pattern access
            ) : 
            {crtc_ra[2:0], crtc_ma[1:0]}) : 
        crtc_ma;

    // Update ASIC RAM write control
    assign asic_ram_wr_en = asic_enabled && 
        (is_sprite_attr_write || is_sprite_pattern_write || 
         (cpu_wr && (cpu_addr[15:8] == 8'hBC)));

// Replace the continuous assignments with:
assign asic_ram_rd = asic_ram_rd_reg;
assign asic_ram_wr = asic_ram_wr_reg;
assign asic_ram_din = asic_ram_din_reg;

// Add new always block:
always @(posedge clk_sys) begin
    if (reset) begin
        asic_ram_addr_reg <= 14'h0000;
        asic_ram_rd_reg <= 1'b0;
        asic_ram_wr_reg <= 1'b0;
        asic_ram_din_reg <= 8'h00;
    end else begin
        // Default values
        asic_ram_rd_reg <= 1'b0;
        asic_ram_wr_reg <= 1'b0;

        // Handle ASIC RAM reads
        if (crtc_clken_actual && crtc_de && asic_enabled) begin
            if (sprite_active_wire) begin
                asic_ram_addr_reg <= (sprite_asic_ram_addr[13:8] == 6'h00) ? 
                    (SPRITE_ATTR_BASE + sprite_asic_ram_addr[4:0]) : 
                    (SPRITE_PATTERN_BASE + sprite_asic_ram_addr[13:0]);
            end else begin
                asic_ram_addr_reg <= {crtc_ra[2:0], crtc_ma[1:0]};
            end
            asic_ram_rd_reg <= 1'b1;
        end

        // Handle ASIC RAM writes
        if (asic_enabled && cpu_wr) begin
            if (cpu_addr[15:8] == 8'hBC) begin
                asic_ram_addr_reg <= cpu_addr[13:0];
                asic_ram_din_reg <= cpu_data;
                asic_ram_wr_reg <= 1'b1;
            end
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


// ------------------------------------------------------------------------------------------------
// Sync signal generation
// ------------------------------------------------------------------------------------------------
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



// ------------------------------------------------------------------------------------------------
// Sprite module instance
// ------------------------------------------------------------------------------------------------
    GX4000_sprite sprite_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        
        // Video interface
        .hpos({1'b0, crtc_ma[8:0]}),  // Extend to 9 bits
        .vpos({4'b0000, crtc_ra}),    // Extend to 9 bits
        .hblank(~crtc_de),
        .vblank(~crtc_vsync),
        
        // Sprite outputs
        .sprite_active(sprite_active),
        .sprite_id(sprite_id),
        
        // Configuration
        .config_sprite(config_sprite),
        .collision_flags(collision_flags),
        
        // ASIC RAM interface
        .asic_ram_addr(sprite_asic_ram_addr),
        .asic_ram_rd(sprite_asic_ram_rd),
        .asic_ram_wr(sprite_asic_ram_wr),
        .asic_ram_din(asic_ram_din),
        .asic_ram_q(asic_ram_q)
    );

    // Update sprite outputs
    always @(posedge clk_sys) begin
        if (reset) begin
            sprite_active_out <= 1'b0;
            sprite_id_out <= 4'h0;
        end else begin
            sprite_active_out <= sprite_active;
            sprite_id_out <= sprite_id;
        end
    end

    // Store previous color values for MRER mode 0x01
    always @(posedge clk_sys) begin
        if (reset) begin
            r_reg_prev <= 8'h00;
            g_reg_prev <= 8'h00;
            b_reg_prev <= 8'h00;
        end else if (crtc_clken_actual && crtc_de) begin
            r_reg_prev <= {2'b00, r_in};
            g_reg_prev <= {2'b00, g_in};
            b_reg_prev <= {2'b00, b_in};
        end
    end


/*
// ------------------------------------------------------------------------------------------------
// CRTC and GA40010 register update logic
// ------------------------------------------------------------------------------------------------
    always @(posedge clk_sys) begin
        if (reset) begin
            crtc_reg_wr   <= 1'b0;
            crtc_reg_sel  <= 4'b0000;
            crtc_reg_data <= 8'h00;
            ga_reg_wr     <= 1'b0;
            ga_reg_sel    <= 4'b0000;
            ga_reg_data   <= 8'h00;
        end else begin
            // Trigger CRTC register write on CPU write to 0xBCxx
            if (cpu_wr && cpu_addr[15:8] == 8'hBC && cpu_addr[1:0] == 2'b00) begin
                crtc_reg_wr   <= 1'b1;
                crtc_reg_sel  <= cpu_data[3:0]; // Example: lower nibble as register index
                crtc_reg_data <= cpu_data;      // Example: full data byte
            end else begin
                crtc_reg_wr <= 1'b0;
            end

            // Trigger GA40010 register write on CPU write to 0xBDxx
            if (cpu_wr && cpu_addr[15:8] == 8'hBD && cpu_addr[1:0] == 2'b00) begin
                ga_reg_wr   <= 1'b1;
                ga_reg_sel  <= cpu_data[3:0]; // Example: lower nibble as register index
                ga_reg_data <= cpu_data;      // Example: full data byte
            end else begin
                ga_reg_wr <= 1'b0;
            end
        end
    end
*/

    localparam SPRITE_ATTR_BASE = 14'h0000;    // Sprite attributes start at 0x0000
    localparam SPRITE_PATTERN_BASE = 14'h0200;  // Sprite patterns start at 0x0200
    localparam SPRITE_ATTR_SIZE = 14'h0020;     // 32 bytes for 16 sprites
    localparam SPRITE_PATTERN_SIZE = 14'h0100;  // 256 bytes per sprite pattern


// ------------------------------------------------------------------------------------------------
// Frame counter
// ------------------------------------------------------------------------------------------------
reg vsync_prev;
always @(posedge clk_sys) begin
    if (reset) begin
        frame_counter <= 8'h00;
        vsync_prev <= 1'b0;
    end else begin
        vsync_prev <= crtc_vsync;
        if (crtc_vsync && !vsync_prev) begin
            frame_counter <= frame_counter + 1;
            $display("[VIDEO_FRAME] Frame %d complete (vsync detected)", frame_counter);
            $display("[VIDEO_CONFIG] ASIC mode=%h, enabled=%b, plus_mode=%b", asic_mode, asic_enabled, plus_mode);
            $display("[VIDEO_CONFIG] Video mode=%h, config_mode=%h", video_mode, config_mode);
            $display("[VIDEO_CONFIG] CRTC: ma=%h, ra=%h, de=%b, vsync=%b, hsync=%b", 
                    crtc_ma, crtc_ra, crtc_de, crtc_vsync, crtc_hsync);
            $display("[VIDEO_CONFIG] ASIC Control: control=%h, status=%h, config=%h", 
                    asic_control, asic_status, asic_config);
            $display("[VIDEO_CONFIG] Video Control: control=%h, status=%h, config=%h", 
                    video_control, video_status, video_config);
        end
    end
end


endmodule 
