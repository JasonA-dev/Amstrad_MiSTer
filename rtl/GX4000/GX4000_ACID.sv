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
        8'hFF,  // First byte
        8'h77,  // Second byte
        8'hB3,  // Third byte
        8'h51,  // Fourth byte
        8'hA8,  // Fifth byte
        8'hD4,  // Sixth byte
        8'h62,  // Seventh byte
        8'h39,  // Eighth byte
        8'h9C,  // Ninth byte
        8'h46,  // Tenth byte
        8'h2B,  // Eleventh byte
        8'h15,  // Twelfth byte
        8'h8A,  // Thirteenth byte
        8'hCD,  // Fourteenth byte (STATE)
        8'hEE,  // Fifteenth byte
        8'hFF,  // Sixteenth byte
        8'hFF   // Final byte
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
    reg [7:0] unlock_addr = 8'h00;

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
            //$display("[ACID] Reset - State: LOCKED, Next byte: %h", UNLOCK_SEQ[0]);
        end
        else if (plus_mode) begin
            // Store last CPU signals for edge detection
            last_cpu_wr <= cpu_wr;
            last_cpu_rd <= cpu_rd;
            last_cpu_data_in <= cpu_data_in;
            last_cpu_addr <= cpu_addr;

            // Handle reads from BC00-BCFF - detect active read
            if (cpu_rd && !last_cpu_rd && cpu_addr[15:8] == 8'hBC) begin
                case (state)
                    LOCKED: begin
                        // First read starts unlock sequence
                        state <= UNLOCKING;
                        seq_index <= 5'd0;
                        status_reg <= UNLOCK_SEQ[0];
                        next_byte <= UNLOCK_SEQ[0];
                        attempt_count <= attempt_count + 1'd1;
                        $display("[ACID] Starting unlock sequence - Attempt %d, Register BC%02X", 
                                attempt_count + 1, cpu_addr[7:0]);
                    end

                    UNLOCKING: begin
                        // Check if correct byte was read
                        if (next_byte == UNLOCK_SEQ[seq_index]) begin
                            received_seq[seq_index] <= next_byte;
                            if (seq_index == 15) begin
                                // STATE byte received - unlock ASIC
                                state <= PERM_UNLOCKED;  // Change to PERM_UNLOCKED
                                seq_index <= seq_index + 1'd1;
                                status_reg <= UNLOCK_SEQ[16];
                                next_byte <= UNLOCK_SEQ[16];
                                $display("[ACID] UNLOCKED! STATE byte (0xCD) read correctly from BC%02X", cpu_addr[7:0]);
                            end
                            else begin
                                seq_index <= seq_index + 1'd1;
                                status_reg <= UNLOCK_SEQ[seq_index + 1'd1];
                                next_byte <= UNLOCK_SEQ[seq_index + 1'd1];
                            end
                        end
                        else begin
                            // Wrong byte read - reset sequence
                            state <= LOCKED;
                            seq_index <= '0;
                            status_reg <= UNLOCK_SEQ[0];
                            next_byte <= UNLOCK_SEQ[0];
                            $display("[ACID] Wrong byte %h read from BC%02X, expected %h - Resetting sequence", 
                                    next_byte, cpu_addr[7:0], UNLOCK_SEQ[seq_index]);
                        end
                    end

                    PERM_UNLOCKED: begin
                        // Stay in PERM_UNLOCKED state, no more unlock attempts needed
                    end

                    default: state <= LOCKED;
                endcase
            end
            
            // Debug write operations - detect rising edge of write
            if (cpu_wr && !last_cpu_wr && cpu_addr[15:8] == 8'hBC) begin
                // Accept both per-address and fixed-address unlock sequences
                // If this is the first write, record the address if not already set
                if (state == LOCKED && seq_index == 0) begin
                    unlock_addr <= cpu_addr[7:0];
                end
                // Check if this is part of the unlock sequence
                if ((cpu_addr[7:0] == cpu_data_in) || (cpu_addr[7:0] == unlock_addr && cpu_data_in == UNLOCK_SEQ[seq_index]) || (cpu_addr[7:0] == 8'h00 && cpu_data_in == UNLOCK_SEQ[seq_index])) begin
                    $display("[ACID] Unlock write: BC%02X = %h (matches address or fixed)", 
                            cpu_addr[7:0], cpu_data_in);
                    // Process as part of unlock sequence
                    case (state)
                        LOCKED: begin
                            if (cpu_data_in == UNLOCK_SEQ[0]) begin
                                state <= UNLOCKING;
                                seq_index <= 1;
                                received_seq[0] <= cpu_data_in;
                                $display("[ACID] Unlock started (fixed or per-address)");
                            end
                        end
                        UNLOCKING: begin
                            if (cpu_data_in == UNLOCK_SEQ[seq_index]) begin
                                received_seq[seq_index] <= cpu_data_in;
                                if ((seq_index == 14 || seq_index == 15)) begin
                                    // STATE byte received - unlock ASIC (support both 15 and 16 byte sequences)
                                    state <= PERM_UNLOCKED;
                                    status_reg <= 8'h00; // Signal unlocked to CPU
                                    next_byte <= 8'h00; // Signal unlocked to CPU
                                    $display("[ACID] UNLOCKED! Complete sequence received (at step %0d)", seq_index);
                                end else begin
                                    seq_index <= seq_index + 1'd1;
                                end
                            end else begin
                                // Wrong value, reset
                                $display("[ACID] Unlock failed at step %0d: got %h, expected %h", seq_index, cpu_data_in, UNLOCK_SEQ[seq_index]);
                                state <= LOCKED;
                                seq_index <= 0;
                            end
                        end
                        default: ;
                    endcase
                end else begin
                    $display("[ACID] Write to BC%02X: Data=%h, Status=%h, State=%s, Step=%d", 
                            cpu_addr[7:0],
                            cpu_data_in,
                            status_reg, 
                            state.name(),
                            seq_index);
                    // Not part of unlock sequence, reset
                    state <= LOCKED;
                    seq_index <= 0;
                end
            end
        end
    end

    // Read logic - using continuous assignment instead of procedural
    assign cpu_data_out = (cpu_rd && plus_mode && cpu_addr == 16'hBC00) ? next_byte : 8'h00;

    // Output assignments
    assign asic_valid = (state == UNLOCKED || state == PERM_UNLOCKED);  // Update to include PERM_UNLOCKED
    assign asic_status = status_reg;

endmodule 


