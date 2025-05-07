module GX4000_joystick
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,
    input         plus_mode,
    
    // Joystick inputs
    input   [6:0] joy1,
    input   [6:0] joy2,
    
    // CPU interface
    input  [15:0] cpu_addr,
    output  [7:0] cpu_data,
    input         cpu_rd,
    
    // Status
    input         joy_swap
);

    // Joystick state
    reg [7:0] joy1_state;
    reg [7:0] joy2_state;
    
    // Map MiSTer joystick inputs to GX4000 format
    always @(posedge clk_sys) begin
        if (reset) begin
            joy1_state <= 8'hFF;
            joy2_state <= 8'hFF;
        end else if (gx4000_mode) begin
            // Joy1 mapping
            joy1_state[0] <= ~joy1[0]; // Right
            joy1_state[1] <= ~joy1[1]; // Left
            joy1_state[2] <= ~joy1[2]; // Down
            joy1_state[3] <= ~joy1[3]; // Up
            joy1_state[4] <= ~joy1[4]; // Fire 1
            joy1_state[5] <= ~joy1[5]; // Fire 2
            joy1_state[6] <= ~joy1[6]; // Fire 3
            joy1_state[7] <= 1'b1;     // Unused
            
            // Joy2 mapping
            joy2_state[0] <= ~joy2[0]; // Right
            joy2_state[1] <= ~joy2[1]; // Left
            joy2_state[2] <= ~joy2[2]; // Down
            joy2_state[3] <= ~joy2[3]; // Up
            joy2_state[4] <= ~joy2[4]; // Fire 1
            joy2_state[5] <= ~joy2[5]; // Fire 2
            joy2_state[6] <= ~joy2[6]; // Fire 3
            joy2_state[7] <= 1'b1;     // Unused
        end
    end
    
    // Read joystick state
    assign cpu_data = (cpu_rd && gx4000_mode) ? 
                     ((cpu_addr == 16'hF7F0) ? joy1_state :
                      (cpu_addr == 16'hF7F1) ? joy2_state : 8'hFF) : 8'hFF;

endmodule 
