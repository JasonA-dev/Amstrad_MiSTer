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
    output  [7:0] asic_status    // ASIC status byte
);

    // Unlock sequence (17 bytes)
    localparam [7:0] UNLOCK_SEQ [0:16] = '{
        8'hFF,  // RQ00 - must be different from 0
        8'h00,  // 0
        8'hFF,  // 255
        8'h77,  // 119
        8'hB3,  // 179
        8'h51,  // 81
        8'hA8,  // 168
        8'hD4,  // 212
        8'h62,  // 98
        8'h39,  // 57
        8'h9C,  // 156
        8'h46,  // 70
        8'h2B,  // 43
        8'h15,  // 21
        8'h8A,  // 138
        8'hCD,  // STATE (205) for UNLOCK
        8'hEE   // ACQ (any value if STATE=205)
    };

    // State machine states
    typedef enum logic [1:0] {
        LOCKED,     // ASIC is locked
        UNLOCKING,  // In process of unlocking
        UNLOCKED,   // ASIC is unlocked
        PERM_UNLOCKED // Permanently unlocked - no more attempts needed
    } acid_state_t;

    // Registers
    acid_state_t state;
    logic [4:0]  seq_index;    // Current position in unlock sequence
    logic [7:0]  status_reg;   // Status register
    logic [31:0] attempt_count; // Debug counter for unlock attempts
    logic [7:0]  received_seq [0:16]; // Store received sequence for debugging
    logic [7:0]  next_byte;    // Next byte to be read by CPU

    // Debug signals
    logic last_cpu_wr;
    logic last_cpu_rd;
    logic [7:0] last_cpu_data_in;
    logic [15:0] last_cpu_addr;

    // Reset logic
    always_ff @(posedge clk_sys) begin
        if (reset) begin
            state <= LOCKED;
            seq_index <= '0;
            status_reg <= UNLOCK_SEQ[0];
            next_byte <= UNLOCK_SEQ[0];
            attempt_count <= '0;
            for (int i = 0; i < 17; i++) received_seq[i] <= 8'h00;
            last_cpu_wr <= 1'b0;
            last_cpu_rd <= 1'b0;
            last_cpu_data_in <= 8'h00;
            last_cpu_addr <= 16'h0000;
            $display("[ACID] Reset - State: LOCKED, Next byte: %h", UNLOCK_SEQ[0]);
        end
        else if (plus_mode) begin
            // Store last CPU signals for edge detection
            last_cpu_wr <= cpu_wr;
            last_cpu_rd <= cpu_rd;
            last_cpu_data_in <= cpu_data_in;
            last_cpu_addr <= cpu_addr;

            // Handle reads from BC00 - detect active read
            if (cpu_rd && cpu_addr == 16'hBC00 && state != PERM_UNLOCKED) begin
                //$display("[ACID] Read from BC00: Data=%h, Current_State=%s, Step=%d, Next_Expected=%h", 
                        //next_byte,
                        //state == LOCKED ? "LOCKED" : state == UNLOCKING ? "UNLOCKING" : "UNLOCKED",
                        //seq_index,
                        //UNLOCK_SEQ[seq_index]);

                case (state)
                    LOCKED: begin
                        if (seq_index == 0) begin
                            // First byte must be non-zero
                            if (next_byte != 8'h00) begin
                                seq_index <= seq_index + 1'd1;
                                status_reg <= UNLOCK_SEQ[seq_index + 1'd1];
                                next_byte <= UNLOCK_SEQ[seq_index + 1'd1];
                                received_seq[0] <= next_byte;
                                //$display("[ACID] Step %d: Valid RQ00 read (%h), advancing to next byte %h", 
                                        //seq_index, next_byte, UNLOCK_SEQ[seq_index + 1'd1]);
                            end else begin
                                //$display("[ACID] Step %d: Invalid RQ00 read (%h) - must be non-zero", 
                                        //seq_index, next_byte);
                            end
                        end
                        else if (next_byte == UNLOCK_SEQ[seq_index]) begin
                            received_seq[seq_index] <= next_byte;
                            if (seq_index == 15) begin
                                // STATE byte received - unlock ASIC
                                state <= PERM_UNLOCKED;  // Change to PERM_UNLOCKED
                                seq_index <= seq_index + 1'd1;
                                status_reg <= UNLOCK_SEQ[16];
                                next_byte <= UNLOCK_SEQ[16];
                                $display("[ACID] UNLOCKED! STATE byte (0xCD) read correctly");
                                $display("[ACID] Full sequence received:");
                                for (int i = 0; i < 16; i++) begin
                                    $display("[ACID] Step %d: Received %h, Expected %h", 
                                            i, received_seq[i], UNLOCK_SEQ[i]);
                                end
                            end
                            else begin
                                seq_index <= seq_index + 1'd1;
                                status_reg <= UNLOCK_SEQ[seq_index + 1'd1];
                                next_byte <= UNLOCK_SEQ[seq_index + 1'd1];
                                //$display("[ACID] Step %d: Correct byte read (%h), advancing to next byte %h", 
                                        //seq_index, next_byte, UNLOCK_SEQ[seq_index + 1'd1]);
                            end
                        end
                        else begin
                            // Wrong byte - reset sequence
                            seq_index <= '0;
                            status_reg <= UNLOCK_SEQ[0];
                            next_byte <= UNLOCK_SEQ[0];
                            attempt_count <= attempt_count + 1'd1;
                            //$display("[ACID] Step %d: Wrong byte read (%h), expected %h. Reset sequence. Attempt: %d", 
                                    //seq_index, next_byte, UNLOCK_SEQ[seq_index], attempt_count + 1'd1);
                            //$display("[ACID] Partial sequence received before error:");
                            for (int i = 0; i < seq_index; i++) begin
                                //$display("[ACID] Step %d: Received %h, Expected %h", 
                                        //i, received_seq[i], UNLOCK_SEQ[i]);
                            end
                        end
                    end

                    UNLOCKED: begin
                        // After ACQ byte, move to PERM_UNLOCKED instead of LOCKED
                        received_seq[16] <= next_byte;
                        seq_index <= '0;
                        status_reg <= UNLOCK_SEQ[0];
                        next_byte <= UNLOCK_SEQ[0];
                        state <= PERM_UNLOCKED;  // Change to PERM_UNLOCKED
                        $display("[ACID] ACQ byte read (%h), moving to PERM_UNLOCKED state", next_byte);
                        $display("[ACID] Complete sequence received:");
                        for (int i = 0; i < 17; i++) begin
                            $display("[ACID] Step %d: Received %h, Expected %h", 
                                    i, received_seq[i], UNLOCK_SEQ[i]);
                        end
                    end

                    PERM_UNLOCKED: begin
                        // Stay in PERM_UNLOCKED state, no more unlock attempts needed
                        $display("[ACID] Already permanently unlocked, ignoring unlock attempts");
                    end

                    default: state <= LOCKED;
                endcase
            end
            
            // Debug write operations - detect rising edge of write
            if (cpu_wr && !last_cpu_wr && cpu_addr == 16'hBC00) begin
                $display("[ACID] Write to BC00: Data=%h, Status=%h, State=%s, Step=%d", 
                        cpu_data_in,
                        status_reg, 
                        state == LOCKED ? "LOCKED" : state == UNLOCKING ? "UNLOCKING" : "UNLOCKED",
                        seq_index);
            end
        end
    end

    // Read logic - using continuous assignment instead of procedural
    assign cpu_data_out = (cpu_rd && plus_mode && cpu_addr == 16'hBC00) ? next_byte : 8'h00;

    // Output assignments
    assign asic_valid = (state == UNLOCKED || state == PERM_UNLOCKED);  // Update to include PERM_UNLOCKED
    assign asic_status = status_reg;

endmodule 

