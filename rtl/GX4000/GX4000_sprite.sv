module GX4000_sprite
(
    input         clk_sys,
    input         reset,
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
    output reg        sprite_active,
    output reg  [3:0] sprite_id,
    
    // Configuration
    input   [7:0] config_sprite,
    output reg [7:0] collision_flags,

    // ASIC RAM interface
    output [13:0] asic_ram_addr,
    output        asic_ram_rd,
    input  [7:0]  asic_ram_q,
    output        asic_ram_wr,
    output [7:0]  asic_ram_din
);

// Add at the top of the module:
reg [13:0] asic_ram_addr_reg;
reg        asic_ram_rd_reg;
reg        asic_ram_wr_reg;
reg [7:0]  asic_ram_din_reg;

    // Add these parameters
    localparam SPRITE_ATTR_BASE = 14'h0000;    // Sprite attributes start at 0x0000
    localparam SPRITE_PATTERN_BASE = 14'h0200;  // Sprite patterns start at 0x0200
    localparam SPRITE_ATTR_SIZE = 14'h0020;     // 32 bytes for 16 sprites
    localparam SPRITE_PATTERN_SIZE = 14'h0100;  // 256 bytes per sprite pattern

    // Expand to 16 sprites
    reg [7:0] sprite_x[0:15];
    reg [7:0] sprite_y[0:15];
    reg [7:0] sprite_pattern[0:15];
    reg [7:0] sprite_color[0:15];
    reg sprite_enable[0:15];
    reg sprite_priority[0:15];
    reg [7:0] sprite_magnification[0:15];
    reg [7:0] sprite_scale_x[0:15];
    reg [7:0] sprite_scale_y[0:15];
    reg [7:0] sprite_rotation[0:15];
    reg [7:0] sprite_center_x[0:15];
    reg [7:0] sprite_center_y[0:15];
    reg [7:0] sprite_flip_x[0:15];
    reg [7:0] sprite_flip_y[0:15];
    reg [7:0] sprite_effect[0:15];

    // Sprite state
    reg [3:0] active_sprite;
    reg [7:0] sprite_line;
    reg [7:0] sprite_pixel_count;
    reg [7:0] collision_reg;
    
    // Sine/Cosine lookup table for sprite rotation
    reg [7:0] sin_table[0:255];
    reg [7:0] cos_table[0:255];
    
    // Sprite collision flags (bitmask, cleared on read)
    reg [7:0] collision_flags_reg;
    reg collision_flags_read;

    // Register mapping and mirroring (MAME-style)
    // 0x6000 + 0x20*n: X position
    // 0x6001 + 0x20*n: Y position
    // 0x6002 + 0x20*n: Pattern
    // 0x6003 + 0x20*n: Color
    // 0x6004 + 0x20*n: Magnification
    // 0x6005 + 0x20*n: Enable
    // 0x6006 + 0x20*n: Priority
    // Mirrored every 0x20 bytes for each sprite (n = 0..15)
    
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
            for (integer i = 0; i < 16; i = i + 1) begin
                sprite_x[i] <= 8'h00;
                sprite_y[i] <= 8'h00;
                sprite_pattern[i] <= 8'h00;
                sprite_color[i] <= 8'h00;
                sprite_magnification[i] <= 8'h00;
                sprite_scale_x[i] <= 8'h40;
                sprite_scale_y[i] <= 8'h40;
                sprite_rotation[i] <= 8'h00;
                sprite_center_x[i] <= 8'h00;
                sprite_center_y[i] <= 8'h00;
                sprite_flip_x[i] <= 8'h00;
                sprite_flip_y[i] <= 8'h00;
                sprite_effect[i] <= 8'h00;
                sprite_enable[i] <= 1'b0;
                sprite_priority[i] <= 1'b0;
            end
            active_sprite <= 4'h0;
            sprite_line <= 8'h00;
            sprite_pixel_count <= 8'h00;
            collision_reg <= 8'h00;
            collision_flags_reg <= 8'h00;
            collision_flags_read <= 1'b0;
            sprite_active <= 1'b0;
            sprite_id <= 4'h0;
        end
    end

    // Register writes
    always @(posedge clk_sys) begin
        if (cpu_wr) begin
            if (cpu_addr[15:12] == 4'h6) begin
                // Sprite control register mapping (mirrored every 0x20)
                integer n = (cpu_addr[11:5] & 7'h0F); // sprite index 0..15
                case (cpu_addr[4:0])
                    5'h00: sprite_x[n] <= cpu_data;
                    5'h01: sprite_y[n] <= cpu_data;
                    5'h02: sprite_pattern[n] <= cpu_data;
                    5'h03: sprite_color[n] <= cpu_data;
                    5'h04: sprite_magnification[n] <= cpu_data;
                    5'h05: sprite_enable[n] <= cpu_data[0];
                    5'h06: sprite_priority[n] <= cpu_data[0];
                    // Add more registers as needed
                    default: ;
                endcase
            end
            // Enhanced sprite transformation registers (as before)
            if (cpu_addr[15:12] == 4'h6) begin
                integer n = (cpu_addr[10:8] & 7'h0F);
                case (cpu_addr[11:0])
                    12'h084: sprite_scale_x[n] <= cpu_data;
                    12'h085: sprite_scale_y[n] <= cpu_data;
                    12'h086: sprite_rotation[n] <= cpu_data;
                    12'h087: sprite_center_x[n] <= cpu_data;
                    12'h088: sprite_center_y[n] <= cpu_data;
                    12'h08A: sprite_flip_x[n] <= cpu_data;
                    12'h08B: sprite_flip_y[n] <= cpu_data;
                    12'h08D: sprite_effect[n] <= cpu_data;
                    // Collision flags register (write clears)
                    12'h083: collision_flags_reg <= 8'h00;
                endcase
            end
            // Collision flags clear on read
            if (cpu_rd && (cpu_addr[15:12] == 4'h6) && (cpu_addr[11:0] == 12'h083)) begin
                collision_flags_read <= 1'b1;
            end else begin
                collision_flags_read <= 1'b0;
            end
            if (collision_flags_read) begin
                collision_flags_reg <= 8'h00;
            end
        end
    end

    // Sprite rendering (MAME-style):
    // Only render enabled sprites, apply priority, magnification, transparency, and collision
    always @(posedge clk_sys) begin
        if (!hblank && !vblank) begin
            // Find highest priority, enabled sprite at this pixel
            reg [3:0] best_sprite = 4'hF;
            reg found = 1'b0;
            reg [8:0] curr_x_start;
            reg [8:0] curr_y_start;
            reg [8:0] curr_x_end;
            reg [8:0] curr_y_end;
            
            for (integer i = 0; i < 16; i = i + 1) begin
                // Calculate sprite boundaries
                curr_x_start = {1'b0, sprite_x[i]};
                curr_y_start = {1'b0, sprite_y[i]};
                curr_x_end = {1'b0, sprite_x[i]} + (sprite_magnification[i][0] ? 9'd32 : 9'd16);
                curr_y_end = {1'b0, sprite_y[i]} + (sprite_magnification[i][0] ? 9'd32 : 9'd16);
                
                if (sprite_enable[i] &&
                    hpos >= curr_x_start && hpos < curr_x_end &&
                    vpos >= curr_y_start && vpos < curr_y_end) begin
                    if (!found || sprite_priority[i]) begin
                        best_sprite = i[3:0];
                        found = 1'b1;
                    end
                end
            end
            
            active_sprite <= best_sprite;
            if (found) begin
                // Magnification: adjust line/pixel count
                if (sprite_magnification[best_sprite][0]) begin
                    sprite_line <= (vpos[7:0] - sprite_y[best_sprite]) >> 1;
                    sprite_pixel_count <= (hpos[7:0] - sprite_x[best_sprite]) >> 1;
                end else begin
                    sprite_line <= vpos[7:0] - sprite_y[best_sprite];
                    sprite_pixel_count <= hpos[7:0] - sprite_x[best_sprite];
                end
                // Collision detection: set bit for this sprite
                collision_flags_reg[best_sprite] <= 1'b1;
            end else begin
                sprite_line <= 8'h00;
                sprite_pixel_count <= 8'h00;
            end
            
            // Update sprite active status using the current sprite's boundaries
            if (found) begin
                curr_x_start = {1'b0, sprite_x[best_sprite]};
                curr_y_start = {1'b0, sprite_y[best_sprite]};
                curr_x_end = {1'b0, sprite_x[best_sprite]} + (sprite_magnification[best_sprite][0] ? 9'd32 : 9'd16);
                curr_y_end = {1'b0, sprite_y[best_sprite]} + (sprite_magnification[best_sprite][0] ? 9'd32 : 9'd16);
                sprite_active <= (hpos >= curr_x_start && hpos < curr_x_end &&
                                vpos >= curr_y_start && vpos < curr_y_end);
            end else begin
                sprite_active <= 1'b0;
            end
            sprite_id <= active_sprite;
        end else begin
            sprite_active <= 1'b0;
            sprite_id <= 4'h0;
        end
    end

    // Modify the sprite pattern address calculation
    wire [13:0] full_sprite_addr = SPRITE_PATTERN_BASE + 
        {sprite_pattern[active_sprite], sprite_line[3:0], sprite_pixel_count[3:0]};

    // Sprite output with effects applied
    reg [7:0] sprite_pixel_with_effects;
    
    always @(*) begin
        // Only output color if enabled and pixel data is nonzero
        if (sprite_enable[active_sprite] && |asic_ram_q) begin
            sprite_pixel_with_effects = sprite_color[active_sprite];
        end else begin
            sprite_pixel_with_effects = 8'h00;
        end
        // Apply sprite effects if active (as before)
        if (|asic_ram_q && config_sprite[0]) begin
            case (sprite_effect[active_sprite])
                8'h01: sprite_pixel_with_effects = sprite_color[active_sprite] | 8'h80;  // Outline
                8'h02: sprite_pixel_with_effects = 8'h80 | {7'b0, sprite_color[active_sprite][6:0] >> 1}; // Shadow
                8'h03: sprite_pixel_with_effects = 8'h80 | (sprite_color[active_sprite][6:0] | 7'h40); // Glow
                8'h04: sprite_pixel_with_effects = {1'b1, ~sprite_color[active_sprite][6:0]}; // Invert
                8'h05: sprite_pixel_with_effects = 8'h80 | (((sprite_color[active_sprite][6:5] * 4) + (sprite_color[active_sprite][4:2] * 4) + (sprite_color[active_sprite][1:0] * 3)) / 9); // Grayscale
                default: ;
            endcase
        end
    end
    
    // Final sprite output
    assign collision_flags = collision_flags_reg;

    // Add sprite download tracking
    reg [3:0] sprite_download_id;
    reg [7:0] sprite_download_offset;
    reg sprite_download_active;
    reg [1:0] download_type;  // 0=none, 1=pattern, 2=attribute



// Replace the continuous assignments with:
assign asic_ram_addr = asic_ram_addr_reg;
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

        // Handle sprite pattern downloads
        if (cpu_wr && (cpu_addr[15:8] == 8'h40)) begin
            asic_ram_addr_reg <= SPRITE_PATTERN_BASE + {sprite_download_id, sprite_download_offset};
            asic_ram_din_reg <= cpu_data;
            asic_ram_wr_reg <= 1'b1;
        end

        // Handle sprite attribute downloads
        if (cpu_wr && (cpu_addr[15:8] == 8'h60) && (cpu_addr[7:5] < 4'h2)) begin
            asic_ram_addr_reg <= SPRITE_ATTR_BASE + {cpu_addr[4:0]};
            asic_ram_din_reg <= cpu_data;
            asic_ram_wr_reg <= 1'b1;
        end

        // Handle sprite pattern reads
        if (sprite_active && !hblank && !vblank) begin
            asic_ram_addr_reg <= SPRITE_PATTERN_BASE + {active_sprite, sprite_line};
            asic_ram_rd_reg <= 1'b1;
        end
    end
end

    // Sprite state handling
    always @(posedge clk_sys) begin
        if (reset) begin
            sprite_active <= 1'b0;
            sprite_id <= 4'h0;
            sprite_download_id <= 4'h0;
            sprite_download_offset <= 8'h00;
            sprite_download_active <= 1'b0;
            download_type <= 2'b00;
            asic_ram_addr_reg <= 14'h0000;
            asic_ram_rd_reg <= 1'b0;
            asic_ram_wr_reg <= 1'b0;
            asic_ram_din_reg <= 8'h00;
        end else begin
            // Default values
            asic_ram_rd_reg <= 1'b0;
            asic_ram_wr_reg <= 1'b0;

            // Handle sprite pattern downloads
            if (cpu_wr && (cpu_addr[15:8] == 8'h40)) begin
                asic_ram_addr_reg <= SPRITE_PATTERN_BASE + {sprite_download_id, sprite_download_offset};
                asic_ram_din_reg <= cpu_data;
                asic_ram_wr_reg <= 1'b1;
                sprite_download_offset <= sprite_download_offset + 1'b1;
                if (sprite_download_offset == 8'hFF) begin
                    sprite_download_id <= sprite_download_id + 1'b1;
                    sprite_download_offset <= 8'h00;
                end
            end

            // Handle sprite attribute downloads
            if (cpu_wr && (cpu_addr[15:8] == 8'h60) && (cpu_addr[7:5] < 4'h2)) begin
                asic_ram_addr_reg <= SPRITE_ATTR_BASE + {cpu_addr[4:0]};
                asic_ram_din_reg <= cpu_data;
                asic_ram_wr_reg <= 1'b1;
            end

            // Handle sprite pattern reads
            if (sprite_active && !hblank && !vblank) begin
                asic_ram_addr_reg <= SPRITE_PATTERN_BASE + {active_sprite, sprite_line};
                asic_ram_rd_reg <= 1'b1;
            end

            // Update sprite active state
            if (!hblank && !vblank) begin
                sprite_active <= (hpos >= sprite_x[active_sprite] && 
                                hpos < (sprite_x[active_sprite] + 16) &&
                                vpos >= sprite_y[active_sprite] && 
                                vpos < (sprite_y[active_sprite] + 16));
                sprite_id <= active_sprite;
            end else begin
                sprite_active <= 1'b0;
                sprite_id <= 4'h0;
            end
        end
    end

endmodule 
