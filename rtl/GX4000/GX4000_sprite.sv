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
    output        sprite_active
);

    // Sprite registers
    reg [7:0] sprite_x[0:7];
    reg [7:0] sprite_y[0:7];
    reg [7:0] sprite_pattern[0:7];
    reg [7:0] sprite_color[0:7];
    reg [7:0] sprite_control[0:7];
    
    // Sprite memory
    reg [7:0] sprite_data[0:2047];
    
    // Sprite state
    reg [2:0] active_sprite;
    reg [7:0] sprite_line;
    reg [7:0] sprite_pixel_count;
    
    // Sprite processing
    always @(posedge clk_sys) begin
        if (reset) begin
            for (integer i = 0; i < 8; i = i + 1) begin
                sprite_x[i] <= 8'h00;
                sprite_y[i] <= 8'h00;
                sprite_pattern[i] <= 8'h00;
                sprite_color[i] <= 8'h00;
                sprite_control[i] <= 8'h00;
            end
            active_sprite <= 3'h0;
            sprite_line <= 8'h00;
            sprite_pixel_count <= 8'h00;
        end else if (gx4000_mode) begin
            // Register writes
            if (cpu_wr) begin
                case (cpu_addr[7:0])
                    8'h50: sprite_x[0] <= cpu_data;
                    8'h51: sprite_y[0] <= cpu_data;
                    8'h52: sprite_pattern[0] <= cpu_data;
                    8'h53: sprite_color[0] <= cpu_data;
                    8'h54: sprite_control[0] <= cpu_data;
                    // ... repeat for sprites 1-7
                endcase
            end
            
            // Sprite rendering
            if (!hblank && !vblank) begin
                // Check for active sprites
                for (integer i = 0; i < 8; i = i + 1) begin
                    if (hpos >= sprite_x[i] && hpos < sprite_x[i] + 16 &&
                        vpos >= sprite_y[i] && vpos < sprite_y[i] + 16) begin
                        active_sprite <= i;
                        sprite_line <= vpos - sprite_y[i];
                        sprite_pixel_count <= hpos - sprite_x[i];
                    end
                end
            end
        end
    end
    
    // Sprite data lookup
    wire [7:0] sprite_data_addr = {sprite_pattern[active_sprite], sprite_line[3:0], sprite_pixel_count[3:0]};
    wire [7:0] sprite_pixel_data = sprite_data[sprite_data_addr];
    
    // Sprite output
    assign sprite_pixel = sprite_pixel_data ? sprite_color[active_sprite] : 8'h00;
    assign sprite_active = sprite_pixel_data != 0;

endmodule 
