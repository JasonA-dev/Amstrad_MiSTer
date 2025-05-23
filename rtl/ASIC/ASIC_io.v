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
    input         joy_swap,
    
    // IO register outputs
    output  [7:0] io_status,
    output  [7:0] io_control,
    output  [7:0] io_data,
    output  [7:0] io_direction,
    output  [7:0] io_interrupt,
    output  [7:0] io_timer,
    output  [7:0] io_clock
);

    // I/O registers
    reg [7:0] joy1_data;
    reg [7:0] joy2_data;
    reg       joy_swap_reg;
    
    // IO state registers
    reg [7:0] status_reg;
    reg [7:0] control_reg;
    reg [7:0] data_reg;
    reg [7:0] direction_reg;
    reg [7:0] interrupt_reg;
    reg [7:0] timer_reg;
    reg [7:0] clock_reg;
    
    // Timer counter
    reg [7:0] timer_counter;
    
    // I/O processing
    always @(posedge clk_sys) begin
        if (reset) begin
            joy1_data <= 8'h00;
            joy2_data <= 8'h00;
            joy_swap_reg <= 0;
            status_reg <= 8'h00;
            control_reg <= 8'h00;
            data_reg <= 8'h00;
            direction_reg <= 8'h00;
            interrupt_reg <= 8'h00;
            timer_reg <= 8'h00;
            clock_reg <= 8'h00;
            timer_counter <= 8'h00;
        end else begin
            // Register writes
            if (cpu_wr) begin
                case (cpu_addr[7:0])
                    // Common registers
                    8'h70: joy_swap_reg <= cpu_data[0];
                    8'h71: status_reg <= cpu_data;
                    8'h72: control_reg <= cpu_data;
                    8'h73: data_reg <= cpu_data;
                    8'h74: direction_reg <= cpu_data;
                    8'h75: interrupt_reg <= cpu_data;
                    8'h76: timer_reg <= cpu_data;
                    8'h77: clock_reg <= cpu_data;
                endcase
            end
            
            // Joystick data update
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
            
            // Timer handling
            if (timer_reg[7]) begin  // Timer enabled
                if (timer_counter == 8'h00) begin
                    timer_counter <= timer_reg[6:0];
                    interrupt_reg[0] <= 1;  // Set timer interrupt
                end else begin
                    timer_counter <= timer_counter - 1;
                end
            end
        end
    end
    
    // I/O output
    assign io_dout = 
        // Standard I/O registers
        (cpu_addr[7:0] == 8'h70) ? {7'h00, joy_swap_reg} :
        (cpu_addr[7:0] == 8'h71) ? status_reg :
        (cpu_addr[7:0] == 8'h72) ? joy1_data :
        (cpu_addr[7:0] == 8'h73) ? joy2_data :
        (cpu_addr[7:0] == 8'h74) ? control_reg :
        (cpu_addr[7:0] == 8'h75) ? data_reg :
        (cpu_addr[7:0] == 8'h76) ? direction_reg :
        (cpu_addr[7:0] == 8'h77) ? interrupt_reg :
        (cpu_addr[7:0] == 8'h78) ? timer_reg :
        (cpu_addr[7:0] == 8'h79) ? clock_reg :
        8'hFF;
        
    // Output assignments
    assign io_status = status_reg;
    assign io_control = control_reg;
    assign io_data = data_reg;
    assign io_direction = direction_reg;
    assign io_interrupt = interrupt_reg;
    assign io_timer = timer_reg;
    assign io_clock = clock_reg;

endmodule 
