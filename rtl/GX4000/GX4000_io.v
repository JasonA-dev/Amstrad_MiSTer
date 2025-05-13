module GX4000_io
(
    input         clk_sys,
    input         reset,
    input         plus_mode,      // Plus mode input
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data,
    input         cpu_wr,
    input         cpu_rd,
    output  [7:0] io_dout,
    
    // Joystick interface
    input   [6:0] joy1,
    input   [6:0] joy2,
    input         joy_swap
);

    // I/O registers
    reg [7:0] joy1_data;
    reg [7:0] joy2_data;
    reg       joy_swap_reg;
    
    // I/O state
    reg [2:0] io_state;
    
    // I/O processing
    always @(posedge clk_sys) begin
        if (reset) begin
            joy1_data <= 8'h00;
            joy2_data <= 8'h00;
            joy_swap_reg <= 0;
            io_state <= 0;
        end else if (plus_mode) begin
            // Register writes
            if (cpu_wr) begin
                case (cpu_addr[7:0])
                    // Common registers
                    8'h70: joy_swap_reg <= cpu_data[0];
                endcase
            end
            
            // Joystick data update for standard ports
            joy1_data <= {
                1'b0,           // Unused
                joy1[6],        // Fire 3
                joy1[5],        // Fire 2
                joy1[4],        // Fire 1
                joy1[3],        // Right
                joy1[2],        // Left
                joy1[1],        // Down
                joy1[0]         // Up
            };
            
            joy2_data <= {
                1'b0,           // Unused
                joy2[6],        // Fire 3
                joy2[5],        // Fire 2
                joy2[4],        // Fire 1
                joy2[3],        // Right
                joy2[2],        // Left
                joy2[1],        // Down
                joy2[0]         // Up
            };
        end
    end
    
    // I/O output
    assign io_dout = 
        // Standard I/O registers
        (cpu_addr[7:0] == 8'h70) ? {7'h00, joy_swap_reg} :
        (cpu_addr[7:0] == 8'h72) ? joy1_data :
        (cpu_addr[7:0] == 8'h73) ? joy2_data :
        8'hFF;

endmodule 
