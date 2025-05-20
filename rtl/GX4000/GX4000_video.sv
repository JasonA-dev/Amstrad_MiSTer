module GX4000_video
(
    input         clk_sys,
    input         reset,
    input         plus_mode,
    
    // CRTC Interface
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
    input  [7:0]  asic_ram_q,
    output        asic_ram_wr,
    output [7:0]  asic_ram_din
);

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

    // Mode handling
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

    // Video output generation
    always @(posedge clk_sys) begin
        if (reset) begin
            r_out <= 4'h0;
            g_out <= 4'h0;
            b_out <= 4'h0;
        end else if (crtc_clken) begin
            if (crtc_de) begin
                case (config_mode)
                    8'h00: begin
                        // Standard CPC mode - use Gate Array colors directly
                        r_out <= {2'b00, r_in};
                        g_out <= {2'b00, g_in};
                        b_out <= {2'b00, b_in};
                        $display("Standard mode: r_in=%b, g_in=%b, b_in=%b", r_in, g_in, b_in);
                    end
                    default: begin
                        if (plus_mode && asic_enabled && asic_ram_rd) begin
                            case (asic_mode)
                                8'h02: begin
                                    // Mode 0x02: Standard Plus mode with palette
                                    case (mrer_mode)
                                        5'h01: begin
                                            // MRER mode 0x01: Enhanced palette mode
                                            // Use palette with additional color processing
                                            r_out <= (palette_latch_r + r_reg_prev) >> 1;
                                            g_out <= (palette_latch_g + g_reg_prev) >> 1;
                                            b_out <= (palette_latch_b + b_reg_prev) >> 1;
                                            $display("ASIC mode 0x02 with MRER 0x01: Using enhanced palette");
                                        end
                                        default: begin
                                            // Standard palette mode
                                            r_out <= palette_latch_r;
                                            g_out <= palette_latch_g;
                                            b_out <= palette_latch_b;
                                            $display("ASIC mode 0x02: Using standard palette");
                                        end
                                    endcase
                                end
                                8'h62: begin
                                    // Mode 0x62: Enhanced Plus mode with sprite priority
                                    if (sprite_active) begin
                                        // Sprite takes priority
                                        r_out <= palette_latch_r;
                                        g_out <= palette_latch_g;
                                        b_out <= palette_latch_b;
                                        $display("ASIC mode 0x62: Using sprite colors");
                                    end else begin
                                        // Use background colors
                                        r_out <= {2'b00, r_in};
                                        g_out <= {2'b00, g_in};
                                        b_out <= {2'b00, b_in};
                                        $display("ASIC mode 0x62: Using background colors");
                                    end
                                end
                                8'h82: begin
                                    // Mode 0x82: Advanced Plus mode with alpha blending
                                    // Blend sprite and background colors
                                    r_out <= (palette_latch_r + {2'b00, r_in}) >> 1;
                                    g_out <= (palette_latch_g + {2'b00, g_in}) >> 1;
                                    b_out <= (palette_latch_b + {2'b00, b_in}) >> 1;
                                    $display("ASIC mode 0x82: Using blended colors");
                                end
                                default: begin
                                    // Fallback to standard Plus mode
                                    r_out <= palette_latch_r;
                                    g_out <= palette_latch_g;
                                    b_out <= palette_latch_b;
                                    $display("Unknown ASIC mode %h: Using default palette", asic_mode);
                                end
                            endcase
                        end else begin
                            // Non-Plus mode or ASIC not reading: Direct 2-bit per channel from motherboard Gate Array
                            r_out <= {2'b00, r_in};
                            g_out <= {2'b00, g_in};
                            b_out <= {2'b00, b_in};
                            $display("Motherboard mode: r_in=%b, g_in=%b, b_in=%b", r_in, g_in, b_in);
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
    end

    // CRTC synchronization
    always @(posedge clk_sys) begin
        if (reset) begin
            scroll_control_sync <= 8'h00;
            split_line_sync <= 8'h00;
            split_addr_sync <= 16'h0000;
            pri_line_sync <= 8'h00;
            pri_control_sync <= 8'h00;
        end else if (crtc_clken) begin
            scroll_control_sync <= scroll_control;
            split_line_sync <= split_line;
            split_addr_sync <= split_addr;
            pri_line_sync <= pri_line;
            pri_control_sync <= pri_control;
        end
    end

    // Video mode handling
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
                        $display("Config mode set to %h", cpu_data);
                    end
                    5'h01: begin
                        mrer_mode <= cpu_data[4:0];
                        $display("MRER mode set to %h", cpu_data[4:0]);
                    end
                    5'h02: begin
                        asic_mode <= cpu_data;
                        // Enable ASIC in Plus mode for modes 0x02, 0x62, and 0x82
                        asic_enabled <= ((cpu_data == 8'h02) || (cpu_data == 8'h62) || (cpu_data == 8'h82)) && plus_mode;
                        $display("ASIC mode set to %h, enabled=%b, plus_mode=%b", 
                                cpu_data, asic_enabled, plus_mode);
                    end
                endcase
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
        end else if (crtc_clken) begin
            if (crtc_de && plus_mode) begin
                // In Plus mode, use ASIC RAM data for palette lookup
                // The address is based on the current mode and position
                palette_pointer <= {crtc_ra[2:0], crtc_ma[1:0]};
                // Use the correct bits from ASIC RAM for each color channel
                palette_latch_r <= {2'b00, asic_ram_q[1:0]};  // Red bits
                palette_latch_g <= {2'b00, asic_ram_q[3:2]};  // Green bits
                palette_latch_b <= {2'b00, asic_ram_q[5:4]};  // Blue bits
            end
        end
    end
                
    // Sprite handling
    always @(posedge clk_sys) begin
        if (reset) begin
            sprite_active <= 1'b0;
            sprite_id <= 4'h0;
            sprite_active_out <= 1'b0;
            sprite_id_out <= 4'h0;
            collision_reg <= 8'h00;
        end else if (crtc_clken) begin
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

    // Priority interrupt generation
    always @(posedge clk_sys) begin
        if (reset) begin
            pri_irq <= 1'b0;
            pri_count <= 8'h00;
        end else if (crtc_clken) begin
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
    assign asic_ram_rd_en = crtc_clken && crtc_de && asic_enabled;  // Only enable reads when ASIC is enabled
    assign asic_ram_wr_en = asic_enabled && cpu_wr && (cpu_addr[15:8] == 8'hBC);
    
    // Debug output for ASIC RAM read conditions
    always @(posedge clk_sys) begin
        if (crtc_clken) begin
            if (crtc_de) begin
                $display("ASIC RAM read conditions: crtc_clken=%b, crtc_de=%b, asic_enabled=%b, plus_mode=%b, ma=%h, ra=%h", 
                        crtc_clken, crtc_de, asic_enabled, plus_mode, crtc_ma, crtc_ra);
            end
        end
    end

    // Debug output for actual ASIC RAM reads
    always @(posedge clk_sys) begin
        if (asic_ram_rd) begin
            $display("ASIC RAM read: addr=%h, data=%h, sprite_active=%b", 
                    asic_ram_addr, asic_ram_q, sprite_active_wire);
        end
    end

    // Sprite ASIC RAM control logic
    assign sprite_asic_ram_rd = asic_ram_rd_en && sprite_active_wire;
    assign sprite_asic_ram_wr = asic_ram_wr_en && sprite_active_wire;
    
    // ASIC RAM interface
    assign asic_ram_addr = asic_enabled ? 
        (sprite_active_wire ? sprite_asic_ram_addr : 
         {crtc_ra[2:0], crtc_ma[1:0]}) : 
        crtc_ma;
    assign asic_ram_rd = asic_ram_rd_en;
    assign asic_ram_wr = asic_ram_wr_en;
    assign asic_ram_din = cpu_data;

    // Sync signal generation
    always @(posedge clk_sys) begin
        if (reset) begin
            sync_filter <= 1'b0;
            hsync_filtered <= 1'b0;
            vsync_filtered <= 1'b0;
            hblank_filtered <= 1'b0;
            vblank_filtered <= 1'b0;
        end else if (crtc_clken) begin
            if (asic_enabled) begin
                // Plus mode: Use ASIC sync timing
                sync_filter <= 1'b1;
                hsync_filtered <= crtc_hsync;
                vsync_filtered <= crtc_vsync;
                hblank_filtered <= ~crtc_de;
                vblank_filtered <= (crtc_ra == 5'h00);
            end else begin
                // Non-Plus mode: Use CRTC sync timing
                sync_filter <= 1'b0;
                hsync_filtered <= crtc_hsync;
                vsync_filtered <= crtc_vsync;
                hblank_filtered <= ~crtc_de;
                vblank_filtered <= (crtc_ra == 5'h00);
            end
        end
    end

    // Sprite module instance
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
        end else if (crtc_clken && crtc_de) begin
            r_reg_prev <= {2'b00, r_in};
            g_reg_prev <= {2'b00, g_in};
            b_reg_prev <= {2'b00, b_in};
        end
    end

endmodule 
