module GX4000_video
(
    input         clk_sys,
    input         reset,
    input         plus_mode,      // Plus mode input
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data,
    input         cpu_wr,
    input         cpu_rd,
    
    // Video input
    input   [1:0] r_in,
    input   [1:0] g_in,
    input   [1:0] b_in,
    input         hblank,
    input         vblank,
    
    // Video output
    output  [3:0] r_out,
    output  [3:0] g_out,
    output  [3:0] b_out,
    
    // Sprite interface outputs (for audio module)
    output        sprite_active,
    output  [3:0] sprite_id,
    output  [7:0] collision_reg
);

    // Color palette registers - 12-bit colors (4 bits per component)
    reg [11:0] primary_palette[0:31];   // Primary palette (6400-643F)
    reg [11:0] secondary_palette[0:31]; // Secondary palette (7Fxx)
    
    // Video registers
    reg [7:0] screen_x;
    reg [7:0] screen_y;
    reg [7:0] video_mode;
    wire [7:0] collision_flags;
    
    // Mode and ROM Enable Register (MRER)
    reg [4:0] mrer_mode;      // Mode selection (bits 4:0)
    reg       mrer_rom_en;    // ROM enable bit
    reg       mrer_plus_mode; // Plus mode enable bit
    reg       mrer_enhanced;  // Enhanced mode enable bit
    
    // Simplified mode selection
    wire is_enhanced_mode = mrer_enhanced || plus_mode;
    wire is_plus_mode = plus_mode || mrer_plus_mode;
    
    // Video state
    reg [1:0] r_reg;
    reg [1:0] g_reg;
    reg [1:0] b_reg;
    
    // Sprite memory - 15 sprites, 1KB each
    reg [7:0] sprite_data[0:15359];  // 15 sprites * 1024 bytes
    
    // Configuration registers
    reg [7:0] config_mode;
    reg [7:0] config_palette;
    reg [7:0] config_sprite;
    reg [7:0] config_video;
    reg [7:0] config_audio;
    reg [7:0] config_io;
    
    // Configuration presets
    reg [7:0] config_preset;
    reg [7:0] config_load[0:7][0:5];  // 8 presets, each with 6 config values
    
    // Previous color registers for effects
    reg [7:0] r_reg_prev;
    reg [7:0] g_reg_prev;
    reg [7:0] b_reg_prev;
    
    // Frame counter for effects
    reg [7:0] frame_counter;
    
    // Video effect registers
    reg [7:0] gray;
    reg [7:0] wave_offset;
    reg [7:0] wave_x;
    reg [7:0] zoom_x;
    reg [7:0] zoom_y;
    reg [7:0] cycle_offset;
    
    // Alpha blending registers
    logic [7:0] alpha;
    
    // Internal position counters for sprite positioning
    reg [8:0] pos_h;
    reg [8:0] pos_v;
    
    // Internal sprite signals
    wire [7:0] sprite_pixel;
    
    // Video processing signals
    wire [11:0] color;
    wire [7:0] grey;
    
    // Calculate color and grey scale values
    wire [4:0] color_index = {r_in, g_in, b_in};  // 3 bits for color selection
    wire [11:0] active_palette = mrer_enhanced ? secondary_palette[color_index] : primary_palette[color_index];
    assign color = active_palette;
    assign grey = (color[11:8] * 9 + color[7:4] * 3 + color[3:0]) / 13;
    
    // Sprite module instance
    GX4000_sprite sprite_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(1'b1),  // Always enabled in GX4000
        .plus_mode(plus_mode),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        
        // Video interface
        .hpos(pos_h),
        .vpos(pos_v),
        .hblank(hblank),
        .vblank(vblank),
        
        // Sprite output
        .sprite_pixel(sprite_pixel),
        .sprite_active(sprite_active),
        .sprite_id(sprite_id),
        
        // Configuration
        .config_sprite(config_sprite),
        .collision_flags(collision_flags)
    );
    
    // Palette pointer for 7Fxx writes
    reg [4:0] palette_pointer;  // Changed to 5 bits to properly handle 0-31 range
    
    // Add latches for palette writes
    reg [3:0] palette_latch_r;
    reg [3:0] palette_latch_g;
    reg [3:0] palette_latch_b;
    
    // Video processing with proper grey scale weighting
    reg [11:0] selected_palette;
    always @(posedge clk_sys) begin
        if (reset) begin
            for (integer i = 0; i < 32; i = i + 1) begin
                primary_palette[i] = 12'h000;
                secondary_palette[i] = 12'h000;
            end
            screen_x <= 8'h00;
            screen_y <= 8'h00;
            video_mode <= 8'h00;
            
            // Initialize configuration
            config_mode <= 8'h00;
            config_palette <= 8'h00;
            config_sprite <= 8'h00;
            config_video <= 8'h00;
            config_audio <= 8'h00;
            config_io <= 8'h00;
            config_preset <= 8'h00;
            
            // Initialize presets
            for (integer i = 0; i < 8; i = i + 1) begin
                for (integer j = 0; j < 6; j = j + 1) begin
                    config_load[i][j] = 8'h00;
                end
            end
            r_reg_prev <= 8'h00;
            g_reg_prev <= 8'h00;
            b_reg_prev <= 8'h00;
            frame_counter <= 8'h00;
            palette_pointer <= 5'h00;  // Initialize to 0
            
            // Initialize sprite memory
            for (integer i = 0; i < 15360; i = i + 1) begin
                sprite_data[i] = 8'h00;
            end
        end else begin
            // Debug output for CPU writes
            if (cpu_wr && cpu_addr[15:14] == 2'b01) begin  // Only 0x4000-0x7FFF range
                //$display("[GX4000_VIDEO] CPU Write: addr=%h data=%h wr=%b rd=%b", 
                //        cpu_addr, cpu_data, cpu_wr, cpu_rd);
                
                // Debug palette writes
                if (cpu_addr[15:6] == 10'h190) begin  // 6400-643F
                    //$display("[GX4000_VIDEO] Palette Write: addr=%h data=%h index=%d", 
                    //        cpu_addr, cpu_data, cpu_addr[5:1]);
                end
                
                // Handle palette writes
                if (cpu_addr[15:8] == 8'h7F) begin
                    case (cpu_addr[7:0])
                        8'h00: begin  // Palette pointer write
                            palette_pointer <= cpu_data[4:0];
                            $display("[GX4000_VIDEO] Palette Pointer Write: %d", cpu_data[4:0]);
                        end
                        8'h01: begin  // Palette RG write
                            palette_latch_r <= cpu_data[7:4];
                            palette_latch_g <= cpu_data[3:0];
                            $display("[GX4000_VIDEO] Palette RG Latch: R=%h G=%h", cpu_data[7:4], cpu_data[3:0]);
                        end
                        8'h02: begin  // Palette B write/commit
                            if (palette_pointer < 32) begin
                                secondary_palette[palette_pointer] <= {palette_latch_r, palette_latch_g, cpu_data[7:4]};
                                $display("[GX4000_VIDEO] Palette Commit: idx=%d R=%h G=%h B=%h", 
                                        palette_pointer, palette_latch_r, palette_latch_g, cpu_data[7:4]);
                                palette_pointer <= palette_pointer + 1'b1; // Auto-increment pointer
                            end
                        end
                        default: begin
                            // Handle mirroring of palette registers
                            if ((cpu_addr[7:0] & 8'hFE) == 8'h00) begin  // Mirror of 7F00
                                palette_pointer <= cpu_data[4:0];
                            end
                            else if ((cpu_addr[7:0] & 8'hFE) == 8'h02) begin  // Mirror of 7F02
                                if (palette_pointer < 32) begin
                                    secondary_palette[palette_pointer] <= {palette_latch_r, palette_latch_g, cpu_data[7:4]};
                                    palette_pointer <= palette_pointer + 1'b1;
                                end
                            end
                        end
                    endcase
                end
            end
            
            // Register writes
            if (cpu_wr) begin
                // Handle writes to video ASIC (0x4000-0x7FFF)
                case (cpu_addr[15:12])
                    4'h4: begin  // 4000h-4FFFh: Sprite image data
                        if (cpu_addr[11:8] < 4'hF) begin  // Valid sprite number (0-14)
                            // Store sprite data in sprite memory
                            sprite_data[{cpu_addr[11:8], cpu_addr[7:0]}] <= cpu_data;
                            $display("[GX4000_VIDEO] Sprite %d Image Data Write: addr=%h data=%h", 
                                    cpu_addr[11:8], cpu_addr, cpu_data);
                        end
                    end
                    
                    4'h6: begin  // 6000h-6FFFh: Sprite control registers
                        case (cpu_addr[11:0])
                            12'h000, 12'h002, 12'h008, 12'h00A, 12'h010, 12'h012, 12'h018, 12'h01A,
                            12'h020, 12'h022, 12'h028, 12'h02A, 12'h030, 12'h032, 12'h038, 12'h03A,
                            12'h040, 12'h042, 12'h048, 12'h04A, 12'h050, 12'h052, 12'h058, 12'h05A,
                            12'h060, 12'h062, 12'h068, 12'h06A, 12'h070, 12'h072, 12'h078, 12'h07A: begin
                                // Sprite X/Y position registers
                                //$display("[GX4000_VIDEO] Sprite %d Position Write: addr=%h data=%h", 
                                        //cpu_addr[7:4], cpu_addr, cpu_data);
                            end
                            
                            12'h004, 12'h00C, 12'h014, 12'h01C, 12'h024, 12'h02C, 12'h034, 12'h03C,
                            12'h044, 12'h04C, 12'h054, 12'h05C, 12'h064, 12'h06C, 12'h074, 12'h07C: begin
                                // Sprite magnification registers
                                //$display("[GX4000_VIDEO] Sprite %d Magnification Write: addr=%h data=%h", 
                                        //cpu_addr[7:4], cpu_addr, cpu_data);
                            end
                            
                            12'h800: begin  // PRI - Programmable raster interrupt
                            //    $display("[GX4000_VIDEO] Raster Interrupt Write: addr=%h data=%h", 
                            //            cpu_addr, cpu_data);
                            end
                            
                            12'h801: begin  // SPLT - Screen split scan line
                            //      $display("[GX4000_VIDEO] Screen Split Write: addr=%h data=%h", 
                            //              cpu_addr, cpu_data);
                            end
                            
                            12'h802, 12'h803: begin  // SSA - Screen split secondary address
                            //    $display("[GX4000_VIDEO] Screen Split Address Write: addr=%h data=%h", 
                            //            cpu_addr, cpu_data);
                            end
                            
                            12'h804: begin  // SSCR - Soft scroll control
                            //    $display("[GX4000_VIDEO] Soft Scroll Control Write: addr=%h data=%h", 
                            //            cpu_addr, cpu_data);
                            end
                            
                            12'hC00, 12'hC02, 12'hC04, 12'hC06, 12'hC08, 12'hC0A: begin  // DMA channel registers
                                //$display("[GX4000_VIDEO] DMA Channel %d Write: addr=%h data=%h", 
                                        //cpu_addr[3:2], cpu_addr, cpu_data);
                            end
                            
                            12'hC0F: begin  // DCSR - DMA control/status
                                //$display("[GX4000_VIDEO] DMA Control/Status Write: addr=%h data=%h", 
                                        //cpu_addr, cpu_data);
                            end
                        endcase
                    end
                    
                    4'h7: begin  // 7000h-7FFFh: Configuration registers
                        case (cpu_data[7:6])
                            2'b00: begin  // Palette pointer register
                                // Store the pointer value (bits 5:0) for next palette write
                                palette_pointer <= cpu_data[4:0];  // Only use lower 5 bits
                                //$display("[GX4000_VIDEO] Secondary Palette Pointer Write: addr=%h data=%h (pointer=%d)", 
                                //        cpu_addr, cpu_data, cpu_data[4:0]);
                            end
                            2'b01: begin  // Palette data register
                                if (palette_pointer < 32) begin
                                    secondary_palette[palette_pointer] <= {cpu_data[7:4], cpu_data[3:0], 4'h0};
                                    $display("[GX4000_VIDEO] Secondary Palette Write: addr=%h data=%h (index=%d)", 
                                            cpu_addr, cpu_data, palette_pointer);
                                end else begin
                                    $display("[GX4000_VIDEO] Warning: Invalid palette pointer %d", palette_pointer);
                                end
                            end
                            2'b10: begin  // Mode and ROM enable register (MRER)
                                if (cpu_addr == 16'h7F8C) begin
                                    // MRER - Mode and ROM enable register
                                    mrer_mode <= cpu_data[4:0];      // Store mode bits
                                    mrer_rom_en <= cpu_data[6];      // Store ROM enable bit
                                    mrer_plus_mode <= cpu_data[7];   // Store Plus mode bit
                                    mrer_enhanced <= (cpu_data[4:0] == 5'h01) ||  // Enhanced video mode
                                                    (cpu_data[4:0] == 5'h02) ||  // Sprite mode
                                                    (cpu_data[4:0] == 5'h03) ||  // Combined mode
                                                    (cpu_data[4:0] == 5'h04) ||  // Audio enhanced mode
                                                    (cpu_data[4:0] == 5'h0C);    // Plus mode
                                    
                                    // Update video mode based on MRER
                                    case (cpu_data[4:0])
                                        5'h00: video_mode <= 8'h00;  // Standard CPC mode
                                        5'h01: video_mode <= 8'h01;  // Enhanced video mode
                                        5'h02: video_mode <= 8'h02;  // Sprite mode
                                        5'h03: video_mode <= 8'h03;  // Combined enhanced video and sprite mode
                                        5'h04: video_mode <= 8'h04;  // Audio enhanced mode
                                        5'h0C: begin                 // Plus mode with enhanced features
                                            video_mode <= 8'h05;     // Special Plus mode
                                            // Enable Plus-specific features
                                            config_mode[0] <= 1'b1;  // Enable enhanced features
                                            config_palette[0] <= 1'b1; // Enable 32-color mode
                                        end
                                        default: begin
                                            video_mode <= 8'h00;     // Default to standard mode
                                            $display("[GX4000_VIDEO] Warning: Unknown mode %h selected, defaulting to standard mode", 
                                                    cpu_data[4:0]);
                                        end
                                    endcase
                                    
                                    $display("[GX4000_VIDEO] Mode and ROM Enable Write: addr=%h data=%h (mode=%h rom_en=%b plus_mode=%b enhanced=%b)", 
                                            cpu_addr, cpu_data, cpu_data[4:0], cpu_data[6], cpu_data[7], mrer_enhanced);
                                end
                            end
                            2'b11: begin  // Memory mapping register (RAM)
                                // RAM mapping configuration
                                //$display("[GX4000_VIDEO] Memory Mapping Write: addr=%h data=%h (page=%h map=%h)", 
                                //        cpu_addr, cpu_data, cpu_data[5:3], cpu_data[2:0]);
                            end
                        endcase
                    end
                endcase
                
                // Primary palette port (6400-643F)
                if (cpu_addr[15:6] == 10'h190) begin  // 6400-643F
                    // Each palette entry is 2 bytes:
                    // First byte: GREEN (D3-D0)
                    // Second byte: RED (D7-D4) and BLUE (D3-D0)
                    if (cpu_addr[0] == 0) begin
                        // First byte - GREEN
                        primary_palette[cpu_addr[5:1]][7:4] <= cpu_data[3:0];
                        //$display("[GX4000_VIDEO] Primary Palette Green Write: addr=%h data=%h (index=%d)", 
                        //        cpu_addr, cpu_data, cpu_addr[5:1]);
                    end else begin
                        // Second byte - RED and BLUE
                        primary_palette[cpu_addr[5:1]][11:8] <= cpu_data[7:4];  // RED
                        primary_palette[cpu_addr[5:1]][3:0]  <= cpu_data[3:0];  // BLUE
                        //$display("[GX4000_VIDEO] Primary Palette Red/Blue Write: addr=%h data=%h (index=%d, red=%h blue=%h)", 
                        //        cpu_addr, cpu_data, cpu_addr[5:1], cpu_data[7:4], cpu_data[3:0]);
                    end
                end
            end
            
            /*
            // Debug color output
            if (!hblank && !vblank) begin
                $display("[GX4000_VIDEO] Color Output: index=%d color=%h r=%h g=%h b=%h", 
                        color_index, color, r_reg, g_reg, b_reg);
            end
            */
            // Video processing with proper grey scale weighting
            if (!hblank && !vblank) begin
                //$display("PIXEL: idx=%d color=%h (R=%h G=%h B=%h) enhanced=%b time=%t", color_index, color, color[11:8], color[7:4], color[3:0], mrer_enhanced, $time);
                // Select palette based on video mode and configuration

                                    
                case (video_mode)
                    8'h00: begin  // Standard CPC mode
                        selected_palette = primary_palette[color_index];
                    end
                    8'h01: begin  // Enhanced video mode
                        selected_palette = mrer_enhanced ? secondary_palette[color_index] : primary_palette[color_index];
                    end
                    8'h02: begin  // Sprite mode
                        if (sprite_active) begin
                            if (config_palette[0]) begin  // 32-color mode
                                selected_palette = secondary_palette[sprite_pixel[4:0]];
                            end else begin  // 16-color mode
                                selected_palette = secondary_palette[{2'b00, sprite_pixel[3:0]}];
                            end
                        end else begin
                            selected_palette = primary_palette[color_index];
                        end
                    end
                    8'h03: begin  // Combined enhanced video and sprite mode
                        if (sprite_active) begin
                            if (config_palette[0]) begin  // 32-color mode
                                selected_palette = secondary_palette[sprite_pixel[4:0]];
                            end else begin  // 16-color mode
                                selected_palette = secondary_palette[{2'b00, sprite_pixel[3:0]}];
                            end
                        end else begin
                            selected_palette = mrer_enhanced ? secondary_palette[color_index] : primary_palette[color_index];
                        end
                    end
                    8'h04: begin  // Audio enhanced mode
                        selected_palette = primary_palette[color_index];
                    end
                    8'h05: begin  // Plus mode
                        if (sprite_active) begin
                            selected_palette = secondary_palette[sprite_pixel[4:0]];
                        end else begin
                            selected_palette = secondary_palette[color_index];
                        end
                    end
                    default: begin
                        selected_palette = primary_palette[color_index];  // Default to primary palette
                    end
                endcase

                // Use grey scale for monochrome output
                if (config_palette[1]) begin  // Monochrome mode
                    reg [7:0] grey = (selected_palette[11:8] * 9 + selected_palette[7:4] * 3 + selected_palette[3:0]) / 13;
                    r_reg <= 2'(grey[7:6]);
                    g_reg <= 2'(grey[7:6]);
                    b_reg <= 2'(grey[7:6]);
                end else begin
                    // Normal color output - use full 4-bit color components
                    r_reg <= 2'(selected_palette[11:8] >> 2);  // Red (4-bit to 2-bit)
                    g_reg <= 2'(selected_palette[7:4] >> 2);   // Green (4-bit to 2-bit)
                    b_reg <= 2'(selected_palette[3:0] >> 2);   // Blue (4-bit to 2-bit)
                end
            end
            
            // Apply configuration
            if (config_mode[0]) begin // Enable enhanced features
                // Apply palette configuration
                if (config_palette[0]) begin // Enable 32-color mode
                    // Use full 32-color palette
                    r_reg <= 2'(secondary_palette[sprite_pixel[4:0]][11:8] >> 2);
                    g_reg <= 2'(secondary_palette[sprite_pixel[4:0]][7:4] >> 2);
                    b_reg <= 2'(secondary_palette[sprite_pixel[4:0]][3:0] >> 2);
                end else begin
                    // Use 16-color mode - only use lower 4 bits of sprite_pixel
                    r_reg <= 2'(secondary_palette[{2'b00, sprite_pixel[3:0]}][11:8] >> 2);
                    g_reg <= 2'(secondary_palette[{2'b00, sprite_pixel[3:0]}][7:4] >> 2);
                    b_reg <= 2'(secondary_palette[{2'b00, sprite_pixel[3:0]}][3:0] >> 2);
                end
                
                // Apply video configuration based on mode bits
                case (config_mode[3:1])
                    3'b000: begin // Standard video mode
                        video_mode <= 8'h00;
                    end
                    3'b001: begin // Enhanced video mode
                        video_mode <= 8'h01;
                    end
                    3'b010: begin // Sprite mode
                        video_mode <= 8'h02;
                    end
                    3'b011: begin // Combined enhanced video and sprite mode
                        video_mode <= 8'h03;
                    end
                    3'b100: begin // Audio enhanced mode
                        video_mode <= 8'h04;
                    end
                    default: begin // Reserved modes
                        video_mode <= 8'h00;
                    end
                endcase
                
                // Apply audio configuration
                if (config_audio[0]) begin // Enable enhanced audio
                    // Configure audio channels
                end
                
                // Apply I/O configuration
                if (config_io[0]) begin // Enable enhanced I/O
                    // Configure I/O ports
                end
                
                // Apply preset configuration
                if (config_preset[7]) begin // Load preset
                    load_preset(config_preset[2:0]);
                end
            end else begin
                // Disable enhanced features
                video_mode <= 8'h00;
                r_reg <= 2'h0;
                g_reg <= 2'h0;
                b_reg <= 2'h0;
            end
            
            // Frame counter for effects
            if (vblank) begin
                frame_counter <= 8'(frame_counter + 1);
            end
            
            // Log mode changes
            //$display("MRER: enhanced=%b mode=%h at time %t", mrer_enhanced, mrer_mode, $time);
        end
    end
    
    // Collision register
    assign collision_reg = collision_flags;

    //////////////////////////////////////////////////////////////////////////////
    // Video Output Multiplexing Logic
    //////////////////////////////////////////////////////////////////////////////
    
    // Sprite activity synchronization for video output timing
    reg sprite_active_sync;
    
    // Synchronize sprite activity signal with video output
    always @(posedge clk_sys) begin
        if (reset)
            sprite_active_sync <= 1'b0;
        else
            sprite_active_sync <= sprite_active;
    end
    
    // Final video output signals
    reg [3:0] final_r;
    reg [3:0] final_g;
    reg [3:0] final_b;
    
    // Add a parameter to enable/disable test pattern
    parameter TEST_PATTERN = 1'b0;
    
    // Add debug counters to track pixel output
    reg [15:0] pixel_counter = 0;
    
    always @(posedge clk_sys) begin
        if (reset) begin
            final_r <= 4'b0000;
            final_g <= 4'b0000;
            final_b <= 4'b0000;
            pixel_counter <= 0;
            frame_counter <= 0;
        end
        else begin
            if (!hblank && !vblank) begin
                pixel_counter <= pixel_counter + 1;
                
                // Log every 1000th pixel for debugging
                if (pixel_counter % 1000 == 0) begin
                    $display("[GX4000_VIDEO] Pixel %d: pos_h=%d pos_v=%d color_idx=%d active_palette=%h", 
                            pixel_counter, pos_h, pos_v, color_index, active_palette);
                end
            end
            
            if (vblank) begin
                frame_counter <= frame_counter + 1;
                $display("[GX4000_VIDEO] Frame %d complete: %d pixels", frame_counter, pixel_counter);
                pixel_counter <= 0;
            end
            
            if (TEST_PATTERN) begin
                // Output a test pattern based on position
                final_r <= pos_h[3:0];
                final_g <= pos_v[3:0];
                final_b <= pos_h[3:0] ^ pos_v[3:0];
            end else begin
                reg [11:0] selected_color;
                reg [4:0] effective_index;
                
                // Determine effective color index
                effective_index = sprite_active ? sprite_pixel[4:0] : color_index;
                
                // Select palette based on mode
                if (is_plus_mode) begin
                    // Plus mode always uses secondary palette
                    selected_color = secondary_palette[effective_index];
                    if (pixel_counter % 1000 == 0) begin
                        $display("[GX4000_VIDEO] Plus mode: idx=%d color=%h", effective_index, selected_color);
                    end
                end else if (is_enhanced_mode) begin
                    // Enhanced mode uses secondary palette for sprites, primary for background
                    selected_color = sprite_active ? secondary_palette[effective_index] : primary_palette[effective_index & 15];
                    if (pixel_counter % 1000 == 0) begin
                        $display("[GX4000_VIDEO] Enhanced mode: sprite=%b idx=%d color=%h", 
                                sprite_active, effective_index, selected_color);
                    end
                end else begin
                    // Standard mode always uses primary palette
                    selected_color = primary_palette[effective_index & 15];
                    if (pixel_counter % 1000 == 0) begin
                        $display("[GX4000_VIDEO] Standard mode: idx=%d color=%h", effective_index, selected_color);
                    end
                end
                
                // Apply monochrome if enabled
                if (config_palette[1]) begin  // Monochrome mode
                    reg [7:0] grey = (selected_color[11:8] * 9 + selected_color[7:4] * 3 + selected_color[3:0]) / 13;
                    final_r <= grey[7:4];
                    final_g <= grey[7:4];
                    final_b <= grey[7:4];
                end else begin
                    // Normal color output
                    final_r <= selected_color[11:8];  // Red (4 bits)
                    final_g <= selected_color[7:4];   // Green (4 bits)
                    final_b <= selected_color[3:0];   // Blue (4 bits)
                end
            end
        end
    end
    
    // Assign the final RGB outputs
    assign r_out = final_r;
    assign g_out = final_g;
    assign b_out = final_b;

    // Save current configuration to a preset
    task save_preset;
        input [2:0] preset_num;
        begin
            config_load[preset_num][0] <= config_mode;
            config_load[preset_num][1] <= config_palette;
            config_load[preset_num][2] <= config_sprite;
            config_load[preset_num][3] <= config_video;
            config_load[preset_num][4] <= config_audio;
            config_load[preset_num][5] <= config_io;
            $display("[GX4000_VIDEO] Saving current config to preset %d", preset_num);
        end
    endtask
    
    // Load configuration from a preset
    task load_preset;
        input [2:0] preset_num;
        begin
            config_mode <= config_load[preset_num][0];
            config_palette <= config_load[preset_num][1];
            config_sprite <= config_load[preset_num][2];
            config_video <= config_load[preset_num][3];
            config_audio <= config_load[preset_num][4];
            config_io <= config_load[preset_num][5];
            $display("[GX4000_VIDEO] Loading config from preset %d", preset_num);
        end
    endtask

endmodule 
