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
    output  [1:0] r_out,
    output  [1:0] g_out,
    output  [1:0] b_out,
    
    // Sprite interface outputs (for audio module)
    output        sprite_active,
    output  [3:0] sprite_id,
    output  [7:0] collision_reg
);

    // Color palette registers
    reg [23:0] palette[0:31]; // 32 colors, 24-bit RGB
    
    // Video registers
    reg [7:0] screen_x;
    reg [7:0] screen_y;
    reg [7:0] video_mode;
    reg [7:0] collision_flags;
    
    // Video state
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
    
    // Configuration presets
    reg [7:0] config_preset;
    reg [7:0] config_load[0:7];
    
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
    
    // Generate position counters
    always @(posedge clk_sys) begin
        if (reset) begin
            pos_h <= 9'd0;
            pos_v <= 9'd0;
        end else begin
            if (hblank) begin
                pos_h <= 9'd0;
                if (vblank)
                    pos_v <= 9'd0;
                else if (!vblank)
                    pos_v <= pos_v + 1'd1;
            end else begin
                pos_h <= pos_h + 1'd1;
            end
        end
    end
    
    //////////////////////////////////////////////////////////////////////////////
    // Sprite Module Instance
    //////////////////////////////////////////////////////////////////////////////
    
    // Connect to the enhanced sprite module
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
        .hpos(pos_h),          // Use internal position counters
        .vpos(pos_v),          // Use internal position counters
        .hblank(hblank),
        .vblank(vblank),
        .sprite_pixel(sprite_pixel),
        .sprite_active(sprite_active),
        .sprite_id(sprite_id),
        .config_sprite(config_sprite),
        .collision_flags(sprite_collision_flags)  // Renamed to avoid multiple drivers
    );
    
    // Create a wire for sprite collision flags to avoid multiple drivers
    wire [7:0] sprite_collision_flags;
    
    // Video processing
    always @(posedge clk_sys) begin
        if (reset) begin
            for (integer i = 0; i < 32; i = i + 1) begin
                palette[i] <= 24'h000000;
            end
            screen_x <= 8'h00;
            screen_y <= 8'h00;
            video_mode <= 8'h00;
            collision_flags <= 8'h00;
            r_reg <= 2'h0;
            g_reg <= 2'h0;
            b_reg <= 2'h0;
            
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
                config_load[i] <= 8'h00;
            end
            r_reg_prev <= 8'h00;
            g_reg_prev <= 8'h00;
            b_reg_prev <= 8'h00;
            frame_counter <= 8'h00;
        end else if (plus_mode) begin
            // Register writes
            if (cpu_wr) begin
                case (cpu_addr[7:0])
                    8'h80: screen_x <= 8'(cpu_data);
                    8'h81: screen_y <= 8'(cpu_data);
                    8'h82: video_mode <= 8'(cpu_data);
                    8'h83: collision_flags <= 8'(cpu_data);
                    
                    // Configuration registers
                    8'h90: config_mode <= 8'(cpu_data);
                    8'h91: config_palette <= 8'(cpu_data);
                    8'h92: config_sprite <= 8'(cpu_data);
                    8'h93: config_video <= 8'(cpu_data);
                    8'h94: config_audio <= 8'(cpu_data);
                    8'h95: config_io <= 8'(cpu_data);
                    8'h96: config_preset <= 8'(cpu_data);
                    8'h98: config_load[cpu_addr[10:8]] <= 8'(cpu_data);
                endcase
                
                // Palette writes
                if (cpu_addr[15:8] == 8'h7F && cpu_addr[7:4] == 4'h6) begin
                    palette[cpu_addr[3:0]] <= {cpu_data, 16'h0000};
                end
            end
            
            // Video processing
            if (!hblank && !vblank) begin
                if (sprite_active) begin
                    // Apply alpha blending for sprites
                    // The sprite module now handles the effects and transformations
                    r_reg <= 2'(palette[{sprite_pixel[7:5], 2'b00}][23:16]);
                    g_reg <= 2'(palette[{sprite_pixel[4:2], 2'b00}][15:8]);
                    b_reg <= 2'(palette[{sprite_pixel[1:0], 3'b000}][7:0]);
                    
                    // Collision detection
                    if (collision_flags[sprite_id]) begin
                        collision_flags[sprite_id] <= 1'b0;
                    end else if (sprite_collision_flags[sprite_id]) begin
                        // Update collision flags from sprite module
                        collision_flags[sprite_id] <= sprite_collision_flags[sprite_id];
                    end
                end else begin
                    // Background color with video mode effects
                    case (video_mode)
                        8'h00: begin // Normal mode
                            r_reg <= 2'(palette[{r_in, 3'b000}][23:16]);
                            g_reg <= 2'(palette[{g_in, 3'b000}][15:8]);
                            b_reg <= 2'(palette[{b_in, 3'b000}][7:0]);
                        end
                        8'h01: begin // Double width
                            r_reg <= 2'(palette[{r_in, 3'b000}][23:16]);
                            g_reg <= 2'(palette[{g_in, 3'b000}][15:8]);
                            b_reg <= 2'(palette[{b_in, 3'b000}][7:0]);
                            if (screen_x[0]) begin
                                r_reg <= 2'(r_reg);
                                g_reg <= 2'(g_reg);
                                b_reg <= 2'(b_reg);
                            end
                        end
                        8'h02: begin // Double height
                            r_reg <= 2'(palette[{r_in, 3'b000}][23:16]);
                            g_reg <= 2'(palette[{g_in, 3'b000}][15:8]);
                            b_reg <= 2'(palette[{b_in, 3'b000}][7:0]);
                            if (screen_y[0]) begin
                                r_reg <= 2'(8'h00);
                                g_reg <= 2'(8'h00);
                                b_reg <= 2'(8'h00);
                            end
                        end
                        8'h03: begin // Interlaced
                            r_reg <= 2'(palette[{r_in, 3'b000}][23:16]);
                            g_reg <= 2'(palette[{g_in, 3'b000}][15:8]);
                            b_reg <= 2'(palette[{b_in, 3'b000}][7:0]);
                            if (screen_y[0]) begin
                                r_reg <= 2'(8'h00);
                                g_reg <= 2'(8'h00);
                                b_reg <= 2'(8'h00);
                            end
                        end
                        8'h04: begin // Scanline
                            r_reg <= 2'(palette[{r_in, 3'b000}][23:16]);
                            g_reg <= 2'(palette[{g_in, 3'b000}][15:8]);
                            b_reg <= 2'(palette[{b_in, 3'b000}][7:0]);
                            if (screen_y[0]) begin
                                r_reg <= 2'(r_reg >> 1);
                                g_reg <= 2'(g_reg >> 1);
                                b_reg <= 2'(b_reg >> 1);
                            end
                        end
                        8'h05: begin // Shadow
                            r_reg <= 2'(palette[{r_in, 3'b000}][23:16]);
                            g_reg <= 2'(palette[{g_in, 3'b000}][15:8]);
                            b_reg <= 2'(palette[{b_in, 3'b000}][7:0]);
                            r_reg <= 2'(r_reg >> 1);
                            g_reg <= 2'(g_reg >> 1);
                            b_reg <= 2'(b_reg >> 1);
                        end
                        8'h06: begin // Ghost
                            r_reg <= 2'(palette[{r_in, 3'b000}][23:16]);
                            g_reg <= 2'(palette[{g_in, 3'b000}][15:8]);
                            b_reg <= 2'(palette[{b_in, 3'b000}][7:0]);
                            r_reg <= 2'((r_reg + 8'h80) >> 1);
                            g_reg <= 2'((g_reg + 8'h80) >> 1);
                            b_reg <= 2'((b_reg + 8'h80) >> 1);
                        end
                        8'h07: begin // Blur
                            r_reg <= 2'((r_reg + r_reg_prev) >> 1);
                            g_reg <= 2'((g_reg + g_reg_prev) >> 1);
                            b_reg <= 2'((b_reg + b_reg_prev) >> 1);
                        end
                        8'h08: begin // Pixelate
                            r_reg <= 2'(r_reg_prev);
                            g_reg <= 2'(g_reg_prev);
                            b_reg <= 2'(b_reg_prev);
                            if (screen_x[1:0] != 2'b00 || screen_y[1:0] != 2'b00) begin
                                r_reg <= 2'(r_reg_prev);
                                g_reg <= 2'(g_reg_prev);
                                b_reg <= 2'(b_reg_prev);
                            end
                        end
                        8'h09: begin // Wave
                            r_reg <= 2'(r_reg_prev);
                            g_reg <= 2'(g_reg_prev);
                            b_reg <= 2'(b_reg_prev);
                            wave_offset = 8'((screen_y * 8'h20) >> 8);
                            wave_x = 8'(screen_x + wave_offset);
                            if (wave_x[7:0] != screen_x[7:0]) begin
                                r_reg <= 2'(r_reg_prev);
                                g_reg <= 2'(g_reg_prev);
                                b_reg <= 2'(b_reg_prev);
                            end
                        end
                        8'h0A: begin // Zoom
                            r_reg <= 2'(r_reg_prev);
                            g_reg <= 2'(g_reg_prev);
                            b_reg <= 2'(b_reg_prev);
                            zoom_x = 8'((screen_x - 8'h40) * 8'h80 >> 7);
                            zoom_y = 8'((screen_y - 8'h40) * 8'h80 >> 7);
                            if (zoom_x[7:0] != screen_x[7:0] || zoom_y[7:0] != screen_y[7:0]) begin
                                r_reg <= 2'(r_reg_prev);
                                g_reg <= 2'(g_reg_prev);
                                b_reg <= 2'(b_reg_prev);
                            end
                        end
                        8'h0B: begin // Color cycle
                            cycle_offset = 8'((frame_counter * 8'h20) >> 8);
                            r_reg <= 2'(palette[{(sprite_pixel[7:5] + cycle_offset[7:5]) & 3'h7, 2'b00}][23:16]);
                            g_reg <= 2'(palette[{(sprite_pixel[4:2] + cycle_offset[4:2]) & 3'h7, 2'b00}][15:8]);
                            b_reg <= 2'(palette[{(sprite_pixel[1:0] + cycle_offset[1:0]) & 2'h3, 3'b000}][7:0]);
                        end
                        8'h0C: begin // RGB shift
                            r_reg <= 2'(r_reg << 1);
                            g_reg <= 2'(g_reg >> 1);
                            b_reg <= 2'(b_reg << 1);
                        end
                        8'h0D: begin // CRT scanlines
                            r_reg <= 2'(palette[{sprite_pixel[7:5], 2'b00}][23:16]);
                            g_reg <= 2'(palette[{sprite_pixel[4:2], 2'b00}][15:8]);
                            b_reg <= 2'(palette[{sprite_pixel[1:0], 3'b000}][7:0]);
                            if (screen_y[0]) begin
                                r_reg <= 2'(r_reg >> 2);
                                g_reg <= 2'(g_reg >> 2);
                                b_reg <= 2'(b_reg >> 2);
                            end
                        end
                        8'h0E: begin // CRT phosphor
                            r_reg <= 2'((r_reg + (r_reg_prev >> 1)) >> 1);
                            g_reg <= 2'((g_reg + (g_reg_prev >> 1)) >> 1);
                            b_reg <= 2'((b_reg + (b_reg_prev >> 1)) >> 1);
                        end
                        8'h0F: begin // CRT bloom
                            r_reg <= 2'((r_reg + (r_reg_prev >> 2)) >> 1);
                            g_reg <= 2'((g_reg + (g_reg_prev >> 2)) >> 1);
                            b_reg <= 2'((b_reg + (b_reg_prev >> 2)) >> 1);
                        end
                    endcase
                end
            end
            
            // Apply configuration
            if (config_mode[0]) begin // Enable enhanced features
                // Apply palette configuration
                if (config_palette[0]) begin // Enable 32-color mode
                    // Use full 32-color palette
                    r_reg <= 2'(palette[{sprite_pixel[7:5], 2'b00}][23:16]);
                    g_reg <= 2'(palette[{sprite_pixel[4:2], 2'b00}][15:8]);
                    b_reg <= 2'(palette[{sprite_pixel[1:0], 3'b000}][7:0]);
                end else begin
                    // Use 16-color mode
                    r_reg <= 2'(palette[{sprite_pixel[7:5], 2'b00}][23:16] & 2'h3);
                    g_reg <= 2'(palette[{sprite_pixel[4:2], 2'b00}][15:8] & 2'h3);
                    b_reg <= 2'(palette[{sprite_pixel[1:0], 3'b000}][7:0] & 2'h3);
                end
                
                // Apply video configuration
                if (config_video[0]) begin // Enable video effects
                    // Use video mode effects
                end else begin
                    // Use normal video mode
                    video_mode <= 8'h00;
                end
                
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
                    case (config_preset[2:0])
                        3'h0: begin
                            config_mode <= config_load[0];
                            config_palette <= config_load[1];
                            config_sprite <= config_load[2];
                            config_video <= config_load[3];
                            config_audio <= config_load[4];
                            config_io <= config_load[5];
                        end
                        3'h1: begin
                            config_mode <= config_load[1];
                            config_palette <= config_load[2];
                            config_sprite <= config_load[3];
                            config_video <= config_load[4];
                            config_audio <= config_load[5];
                            config_io <= config_load[6];
                        end
                        // ... more preset cases ...
                    endcase
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
    reg [1:0] final_r, final_g, final_b;
    
    always @(posedge clk_sys) begin
        if (reset) begin
            final_r <= 2'b00;
            final_g <= 2'b00;
            final_b <= 2'b00;
        end
        else begin
            if (plus_mode) begin
                // In Plus mode with sprites active
                if (sprite_active_sync) begin
                    // If sprite is active, use processed video with sprites
                    final_r <= r_reg;
                    final_g <= g_reg;
                    final_b <= b_reg;
                end else begin
                    // No sprite active, just use the standard video input
                    final_r <= r_in;
                    final_g <= g_in;
                    final_b <= b_in;
                end
            end else begin
                // Not in Plus mode, just pass through the original signals
                final_r <= r_in;
                final_g <= g_in;
                final_b <= b_in;
            end
        end
    end
    
    // Assign the final RGB outputs
    assign r_out = final_r;
    assign g_out = final_g;
    assign b_out = final_b;

endmodule 
