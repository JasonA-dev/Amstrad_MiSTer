module GX4000_ACID
(
    input         clk_sys,
    input         reset,
    input         plus_mode,      // Plus mode enable
    
    // CPU interface
    input  [15:0] cpu_addr,      // CPU address bus
    input   [7:0] cpu_data_in,   // CPU data input
    input         cpu_wr,        // CPU write strobe
    input         cpu_rd,        // CPU read strobe
    output  [7:0] cpu_data_out,  // CPU data output
    
    // Status outputs
    output        asic_valid,    // ASIC validation status
    output  [7:0] asic_status   // ASIC status byte
);

    // ASIC unlock sequence (17 bytes)
    localparam [7:0] UNLOCK_SEQ [0:16] = '{
        8'hFF,  // BC06
        8'h00,  // BC05
        8'hFF,  // BC04
        8'h77,  // BC03
        8'hB3,  // BC02
        8'h51,  // BC01
        8'hA8,  // BC00
        8'hD4,  // BC06
        8'h62,  // BC05
        8'h39,  // BC04
        8'h9C,  // BC03
        8'h46,  // BC02
        8'h2B,  // BC01
        8'h15,  // BC00
        8'h8A,  // BC06
        8'hCD,  // BC05
        8'hEE   // BC04
    };

    // Unlock sequence state
    reg [4:0]  unlock_step;    // Current step in unlock sequence (0-16)
    reg        asic_locked;    // ASIC lock status
    reg [7:0]  status_byte;    // Status byte (next expected value)
    reg [31:0] unlock_attempts;  // Counter for unlock attempts

    // Debug counter
    reg [31:0] debug_counter;

    // Reset and initialization
    always @(posedge clk_sys) begin
        if (reset) begin
            unlock_step <= 5'd0;
            asic_locked <= 1'b1;
            status_byte <= UNLOCK_SEQ[0];  // Initialize with first expected byte
            unlock_attempts <= 32'd0;
            debug_counter <= 32'd0;
            $display("DEBUG: ACID Reset - locked=1, step=0, expect=%h", UNLOCK_SEQ[0]);
        end
    end
    
    // Main unlock sequence handler
    always @(posedge clk_sys) begin
        if (!reset && plus_mode) begin
            // Handle writes to BC00-BC06 (unlock sequence)
            if (cpu_wr && (cpu_addr[15:3] == 13'h17C0)) begin  // Check for BC00-BC07 range
                debug_counter <= debug_counter + 1;
                unlock_attempts <= unlock_attempts + 1;
                
                $display("DEBUG: ACID Write %d (Attempt %d) - addr=%h data=%h step=%d expect=%h plus_mode=%b", 
                        debug_counter, unlock_attempts, cpu_addr, cpu_data_in, unlock_step, UNLOCK_SEQ[unlock_step], plus_mode);

                // Check if written byte matches expected sequence
                if (cpu_data_in == UNLOCK_SEQ[unlock_step]) begin
                    // Correct byte received
                    if (unlock_step == 5'd15) begin
                        // STATE byte (0xCD) received correctly - unlock ASIC
                        asic_locked <= 1'b0;
                        $display("DEBUG: ACID Unlock successful! (Attempt %d)", unlock_attempts);
                    end
                    
                    // Advance to next step
                    if (unlock_step == 5'd16) begin
                        unlock_step <= 5'd0;
                        status_byte <= UNLOCK_SEQ[0];  // Reset to first expected byte
                        $display("DEBUG: ACID Sequence complete, resetting to start (Attempt %d)", unlock_attempts);
                    end else begin
                        unlock_step <= unlock_step + 1'd1;
                        status_byte <= UNLOCK_SEQ[unlock_step + 1'd1];  // Set next expected byte
                        $display("DEBUG: ACID Advancing to step %d, next expect=%h (Attempt %d)", 
                                unlock_step + 1'd1, UNLOCK_SEQ[unlock_step + 1'd1], unlock_attempts);
                    end
                end else begin
                    // Incorrect byte - reset sequence
                    unlock_step <= 5'd0;
                    asic_locked <= 1'b1;
                    status_byte <= UNLOCK_SEQ[0];
                    $display("DEBUG: ACID Sequence reset - got %h but expected %h (Attempt %d)", 
                            cpu_data_in, UNLOCK_SEQ[unlock_step], unlock_attempts);
                end
            end
            
            // Handle reads from BC00 (status)
            if (cpu_rd && cpu_addr == 16'hBC00) begin
                $display("DEBUG: ACID Read - addr=%h status=%h locked=%b step=%d (Attempt %d)",
                        cpu_addr, status_byte, asic_locked, unlock_step, unlock_attempts);
            end
        end
    end

    // Read handler 
    reg [7:0] read_data;
    always @(*) begin
        read_data = 8'h00;  // Default to 0
        
        if (cpu_rd && plus_mode) begin
            case (cpu_addr[15:3])
                13'h17C0: begin  // BC00-BC07 range
                    case (cpu_addr[2:0])
                        3'b000: read_data = status_byte;        // BC00: Return next expected byte
                        3'b001: read_data = {7'b0000000, asic_locked};  // BC01: Return lock status
                        default: read_data = 8'h00;
                    endcase
                end
                default: read_data = 8'h00;
            endcase
        end
    end

    // Output assignments
    assign cpu_data_out = read_data;
    assign asic_valid = ~asic_locked;
    assign asic_status = status_byte;

endmodule 

