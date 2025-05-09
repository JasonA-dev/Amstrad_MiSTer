module GX4000_io
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,
    input         plus_mode,    // New input for Plus mode
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data,
    input         cpu_wr,
    input         cpu_rd,
    output  [7:0] io_dout,
    
    // Joystick interface
    input   [6:0] joy1,
    input   [6:0] joy2,
    input         joy_swap,
    
    // Printer interface
    output  [7:0] printer_data,
    output        printer_strobe,
    input         printer_busy,
    input         printer_ack,
    
    // RS232 interface
    output  [7:0] rs232_data,
    output        rs232_tx,
    input         rs232_rx,
    output        rs232_rts,
    input         rs232_cts,
    
    // Playcity interface
    output  [7:0] playcity_data,
    output        playcity_wr,
    output        playcity_rd,
    input   [7:0] playcity_din,
    input         playcity_ready,
    
    // Peripheral interface
    output  [7:0] peripheral_data,
    output        peripheral_ready,
    input         peripheral_ack
);

    // I/O registers
    reg [7:0] joy1_data;
    reg [7:0] joy2_data;
    reg [7:0] peripheral_reg;
    reg       joy_swap_reg;
    
    // Plus-specific registers
    reg [7:0] printer_reg;
    reg [7:0] rs232_reg;
    reg [7:0] playcity_reg;
    reg       rs232_tx_reg;
    reg       playcity_enable;
    
    // I/O state
    reg [2:0] io_state;
    reg       peripheral_busy;
    reg       printer_busy_state;
    reg       rs232_busy;
    reg       playcity_busy;
    
    // Joystick state for GX4000 compatibility
    reg [7:0] joy1_state;
    reg [7:0] joy2_state;
    
    // I/O processing
    always @(posedge clk_sys) begin
        if (reset) begin
            joy1_data <= 8'h00;
            joy2_data <= 8'h00;
            peripheral_reg <= 8'h00;
            joy_swap_reg <= 0;
            io_state <= 0;
            peripheral_busy <= 0;
            
            // Plus-specific reset
            printer_reg <= 8'h00;
            rs232_reg <= 8'h00;
            playcity_reg <= 8'h00;
            rs232_tx_reg <= 0;
            playcity_enable <= 0;
            printer_busy_state <= 0;
            rs232_busy <= 0;
            playcity_busy <= 0;
            
            // GX4000 joystick state reset
            joy1_state <= 8'hFF;
            joy2_state <= 8'hFF;
        end else if (gx4000_mode || plus_mode) begin
            // Register writes
            if (cpu_wr) begin
                case (cpu_addr[7:0])
                    // Common registers
                    8'h70: joy_swap_reg <= cpu_data[0];
                    8'h71: peripheral_reg <= cpu_data;
                    
                    // Plus-specific registers
                    8'h74: printer_reg <= cpu_data;
                    8'h75: rs232_reg <= cpu_data;
                    8'h76: playcity_reg <= cpu_data;
                    8'h77: playcity_enable <= cpu_data[0];
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
            
            // GX4000 style joystick mapping
            // Joy1 mapping (inverted logic compared to standard)
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
            
            // Printer handling
            if (printer_ack) begin
                printer_busy_state <= 0;
            end else if (cpu_wr && cpu_addr[7:0] == 8'h74) begin
                printer_busy_state <= 1;
            end
            
            // RS232 handling
            if (rs232_cts) begin
                rs232_busy <= 0;
            end else if (cpu_wr && cpu_addr[7:0] == 8'h75) begin
                rs232_busy <= 1;
            end
            
            // Playcity handling
            if (playcity_ready) begin
                playcity_busy <= 0;
            end else if (cpu_wr && cpu_addr[7:0] == 8'h76) begin
                playcity_busy <= 1;
            end
            
            // Peripheral handling
            if (peripheral_ack) begin
                peripheral_busy <= 0;
            end else if (cpu_wr && cpu_addr[7:0] == 8'h71) begin
                peripheral_busy <= 1;
            end
        end
    end
    
    // I/O output - extended to handle GX4000 joystick addresses
    assign io_dout = 
        // Standard I/O registers
        (cpu_addr[7:0] == 8'h70) ? {7'h00, joy_swap_reg} :
        (cpu_addr[7:0] == 8'h71) ? peripheral_reg :
        (cpu_addr[7:0] == 8'h72) ? joy1_data :
        (cpu_addr[7:0] == 8'h73) ? joy2_data :
        (cpu_addr[7:0] == 8'h74) ? printer_reg :
        (cpu_addr[7:0] == 8'h75) ? rs232_reg :
        (cpu_addr[7:0] == 8'h76) ? playcity_reg :
        (cpu_addr[7:0] == 8'h77) ? {7'h00, playcity_enable} :
        
        // GX4000 joystick addresses
        (cpu_addr == 16'hF7F0) ? joy1_state :
        (cpu_addr == 16'hF7F1) ? joy2_state :
        
        8'hFF;
    
    // Peripheral interface
    assign peripheral_data = peripheral_reg;
    assign peripheral_ready = peripheral_busy;
    
    // Printer interface
    assign printer_data = printer_reg;
    assign printer_strobe = printer_busy_state;
    
    // RS232 interface
    assign rs232_data = rs232_reg;
    assign rs232_tx = rs232_tx_reg;
    assign rs232_rts = rs232_busy;
    
    // Playcity interface
    assign playcity_data = playcity_reg;
    assign playcity_wr = playcity_busy && playcity_enable;
    assign playcity_rd = cpu_rd && (cpu_addr[7:0] == 8'h76) && playcity_enable;
    
    // Joystick swap is handled via the joy_swap input
endmodule 
