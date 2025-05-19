module GX4000_sprite
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,
    input         plus_mode,
    
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
    
    // Sprite output
    output  [7:0] sprite_pixel,
    output        sprite_active,
    output  [3:0] sprite_id,
    
    // Configuration
    input   [7:0] config_sprite,
    output  [7:0] collision_flags,

    // ASIC RAM interface
    output [13:0] asic_ram_addr,
    output        asic_ram_rd,
    input  [7:0]  asic_ram_q,
    output        asic_ram_wr,
    output [7:0]  asic_ram_din
);

    // Basic sprite registers
    reg [7:0] sprite_x[0:7];
    reg [7:0] sprite_y[0:7];
    reg [7:0] sprite_pattern[0:7];
    reg [7:0] sprite_color[0:7];
    
    // Enhanced sprite transformation registers
    reg [7:0] sprite_scale_x[0:7];
    reg [7:0] sprite_scale_y[0:7];
    reg [7:0] sprite_rotation[0:7];
    reg [7:0] sprite_center_x[0:7];
    reg [7:0] sprite_center_y[0:7];
    reg [7:0] sprite_flip_x[0:7];
    reg [7:0] sprite_flip_y[0:7];
    reg [7:0] sprite_effect[0:7];
    
    // Sprite state
    reg [2:0] active_sprite;
    reg [7:0] sprite_line;
    reg [7:0] sprite_pixel_count;
    reg [7:0] collision_reg;
    
    // Sine/Cosine lookup table for sprite rotation
    reg [7:0] sin_table[0:255];
    reg [7:0] cos_table[0:255];
    
    // Initialize lookup tables with pre-calculated fixed-point values
    initial begin
        // Pre-calculated sine values (scaled to 8-bit signed)
        for (int i = 0; i < 256; i = i + 1) begin
            // Convert angle to radians and calculate sin/cos
            // Scale to 8-bit signed value (-128 to 127)
            // Use fixed-point arithmetic instead of $rtoi
            sin_table[i] = 8'((i < 128) ? (i * 127 / 128) : ((256 - i) * 127 / 128));
            cos_table[i] = 8'((i < 64) ? (127 - (i * 127 / 64)) : 
                           (i < 192) ? ((i - 64) * 127 / 128 - 127) : 
                           (127 - ((i - 192) * 127 / 64)));
        end
    end
    
    // Reset logic
    always @(posedge clk_sys) begin
        if (reset) begin
            for (integer i = 0; i < 8; i = i + 1) begin
                // Basic sprite registers
                sprite_x[i] <= 8'h00;
                sprite_y[i] <= 8'h00;
                sprite_pattern[i] <= 8'h00;
                sprite_color[i] <= 8'h00;
                
                // Enhanced sprite transformation registers
                sprite_scale_x[i] <= 8'h40;  // 1.0 scale
                sprite_scale_y[i] <= 8'h40;  // 1.0 scale
                sprite_rotation[i] <= 8'h00; // 0 degrees
                sprite_center_x[i] <= 8'h00;
                sprite_center_y[i] <= 8'h00;
                sprite_flip_x[i] <= 8'h00;
                sprite_flip_y[i] <= 8'h00;
                sprite_effect[i] <= 8'h00;
            end
            active_sprite <= 3'h0;
            sprite_line <= 8'h00;
            sprite_pixel_count <= 8'h00;
            collision_reg <= 8'h00;
        end
    end

    // Register writes
    always @(posedge clk_sys) begin
        if (cpu_wr) begin
            case (cpu_addr[15:12])
                4'h6: begin  // 6000h-6FFFh: Sprite control registers
                    case (cpu_addr[11:0])
                        // Basic sprite registers
                        12'h000: sprite_x[0] <= cpu_data;
                        12'h001: sprite_y[0] <= cpu_data;
                        12'h002: sprite_pattern[0] <= cpu_data;
                        12'h003: sprite_color[0] <= cpu_data;
                        // ... repeat for sprites 1-7
                        
                        // Enhanced sprite transformation registers
                        12'h084: sprite_scale_x[cpu_addr[10:8]] <= cpu_data;
                        12'h085: sprite_scale_y[cpu_addr[10:8]] <= cpu_data;
                        12'h086: sprite_rotation[cpu_addr[10:8]] <= cpu_data;
                        12'h087: sprite_center_x[cpu_addr[10:8]] <= cpu_data;
                        12'h088: sprite_center_y[cpu_addr[10:8]] <= cpu_data;
                        12'h08A: sprite_flip_x[cpu_addr[10:8]] <= cpu_data;
                        12'h08B: sprite_flip_y[cpu_addr[10:8]] <= cpu_data;
                        12'h08D: sprite_effect[cpu_addr[10:8]] <= cpu_data;
                        
                        // Collision flags register
                        12'h083: collision_reg <= cpu_data;
                    endcase
                end
            endcase
        end
    end

    // Sprite rendering
    always @(posedge clk_sys) begin
        if (!hblank && !vblank) begin
            // Check for active sprites
            for (integer i = 0; i < 8; i = i + 1) begin
                if (hpos >= sprite_x[i] && hpos < sprite_x[i] + 16 &&
                    vpos >= sprite_y[i] && vpos < sprite_y[i] + 16) begin
                    active_sprite <= i[2:0];
                    sprite_line <= vpos[7:0] - sprite_y[i];
                    sprite_pixel_count <= hpos[7:0] - sprite_x[i];
                    
                    // Apply transformations if enabled
                    if (config_sprite[0]) begin // Enable sprite transformations
                        // Get sprite transformation parameters
                        reg [7:0] angle = sprite_rotation[i];
                        reg [7:0] scale_x = sprite_scale_x[i];
                        reg [7:0] scale_y = sprite_scale_y[i];
                        reg [7:0] center_x = sprite_center_x[i];
                        reg [7:0] center_y = sprite_center_y[i];
                        
                        // Apply scaling
                        reg [15:0] rot_x = ((hpos[7:0] - center_x) * scale_x) >> 6;
                        reg [15:0] rot_y = ((vpos[7:0] - center_y) * scale_y) >> 6;
                        
                        // Apply rotation
                        reg [7:0] cos_angle = cos_table[angle];
                        reg [7:0] sin_angle = sin_table[angle];
                        rot_x = (rot_x * cos_angle - rot_y * sin_angle) >> 8;
                        rot_y = (rot_x * sin_angle + rot_y * cos_angle) >> 8;
                        
                        // Apply flipping
                        if (sprite_flip_x[i]) begin
                            rot_x = -rot_x;
                        end
                        if (sprite_flip_y[i]) begin
                            rot_y = -rot_y;
                        end
                        
                        // Update collision detection
                        collision_reg[i] <= 1'b1;
                    end
                end
            end
        end
    end

    // Create a proper address for sprite_data lookup
    wire [10:0] full_sprite_addr = {sprite_pattern[active_sprite], sprite_line[3:0], sprite_pixel_count[3:0]};
    wire [7:0] sprite_pixel_data = asic_ram_q;
    
    // Sprite output with effects applied
    reg [7:0] sprite_pixel_with_effects;
    
    always @(*) begin
        // Default - no effect
        sprite_pixel_with_effects = sprite_pixel_data ? sprite_color[active_sprite] : 8'h00;
        
        // Apply sprite effects if active
        if (sprite_pixel_data && config_sprite[0]) begin
            case (sprite_effect[active_sprite])
                8'h01: begin // Outline effect
                    sprite_pixel_with_effects = sprite_color[active_sprite] | 8'h80;  // Add highlight bit
                end
                8'h02: begin // Shadow effect
                    sprite_pixel_with_effects = 8'h80 | {7'b0, sprite_color[active_sprite][6:0] >> 1};
                end
                8'h03: begin // Glow effect
                    sprite_pixel_with_effects = 8'h80 | (sprite_color[active_sprite][6:0] | 7'h40);
                end
                8'h04: begin // Invert effect
                    sprite_pixel_with_effects = {1'b1, ~sprite_color[active_sprite][6:0]};
                end
                8'h05: begin // Grayscale effect
                    sprite_pixel_with_effects = 8'h80 | (((sprite_color[active_sprite][6:5] * 4) + 
                                                         (sprite_color[active_sprite][4:2] * 4) + 
                                                         (sprite_color[active_sprite][1:0] * 3)) / 9);
                end
                default: begin // No effect
                    sprite_pixel_with_effects = sprite_pixel_data ? sprite_color[active_sprite] : 8'h00;
                end
            endcase
        end
    end
    
    // Final sprite output
    assign sprite_pixel = sprite_pixel_with_effects;
    assign sprite_active = sprite_pixel_data != 0;
    assign collision_flags = collision_reg;

    // When fetching sprite data for rendering:
    // set asic_ram_addr to the sprite data address
    // set asic_ram_rd to 1 for one cycle
    // use asic_ram_q as the fetched value
    assign asic_ram_addr = {sprite_pattern[active_sprite], sprite_line[3:0], sprite_pixel_count[3:0]};
    assign asic_ram_rd = 1;
    assign asic_ram_wr = 0;
    assign asic_ram_din = 0;

endmodule 
