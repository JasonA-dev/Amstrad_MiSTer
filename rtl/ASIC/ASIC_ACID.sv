module ASIC_ACID
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
    
    // Hardware register inputs
    input   [7:0] sprite_control,    // Sprite control register
    input   [7:0] sprite_collision,  // Sprite collision register
    input   [7:0] audio_control,     // Audio control register
    input   [7:0] audio_status,      // Audio status register
    input   [7:0] video_status,      // Video status register
    
    // ASIC RAM public interface
    input  [13:0] asic_ram_addr,
    input         asic_ram_rd,
    input         asic_ram_wr,
    input  [7:0]  asic_ram_din,
    output [7:0]  asic_ram_q,
    
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

    // Read logic - using continuous assignment instead of procedural
    reg [7:0] asic_register;
    reg [7:0] register_index;

    // Sequential register reading for ASIC page (0x4000-0x7FFF)
    always @(posedge clk_sys) begin
        if (reset) begin
            register_index <= 8'h00;
            asic_register <= 8'h00;
        end else if (plus_mode && cpu_rd && (cpu_addr >= 16'h4000) && (cpu_addr <= 16'h7FFF)) begin
            // Increment register index on each read
            register_index <= register_index + 1'd1;
            
            // Return different register values based on index
            case (register_index)
                8'h00: asic_register <= video_status;    // Video status register
                8'h01: asic_register <= sprite_control;  // Sprite control register
                8'h02: asic_register <= sprite_collision;// Sprite collision register
                8'h03: asic_register <= audio_control;   // Audio control register
                8'h04: asic_register <= audio_status;    // Audio status register
                8'h05: asic_register <= 8'h00;           // Reserved
                8'h06: asic_register <= 8'h00;           // Reserved
                8'h07: asic_register <= 8'h00;           // Reserved
                default: asic_register <= 8'h00;         // Return 0 for other reads
            endcase
        end
    end

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
        end
        else if (plus_mode) begin
            // Store last CPU signals for edge detection
            last_cpu_wr <= cpu_wr;
            last_cpu_rd <= cpu_rd;
            last_cpu_data_in <= cpu_data_in;
            last_cpu_addr <= cpu_addr;

            // Handle reads from BC00-BCFF - detect active read
            if (cpu_rd && !last_cpu_rd && cpu_addr[15:8] == 8'hBC) begin
                $display("ACID read");
                case (state)
                    LOCKED: begin
                        $display("ACID locked");
                        // First read starts unlock sequence
                        state <= UNLOCKING;
                        seq_index <= 5'd0;
                        status_reg <= UNLOCK_SEQ[0];
                        next_byte <= UNLOCK_SEQ[0];
                        attempt_count <= attempt_count + 1'd1;
                    end

                    UNLOCKING: begin
                        $display("ACID unlocking");
                        // Check if correct byte was read
                        if (next_byte == UNLOCK_SEQ[seq_index]) begin
                            received_seq[seq_index] <= next_byte;
                            if (seq_index == 15) begin
                                // STATE byte received - unlock ASIC
                                $display("ACID unlocked");
                                state <= PERM_UNLOCKED;  // Change to PERM_UNLOCKED
                                seq_index <= seq_index + 1'd1;
                                status_reg <= UNLOCK_SEQ[16];
                                next_byte <= UNLOCK_SEQ[16];
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
                        end
                    end

                    PERM_UNLOCKED: begin
                        // Stay in PERM_UNLOCKED state, no more unlock attempts needed
                    end

                    default: state <= LOCKED;
                endcase
            end
        end
    end

    // Output assignment based on address range
    assign cpu_data_out = 
        (cpu_addr >= 16'h4000 && cpu_addr <= 16'h7FFF) ? asic_ram_q :
        (cpu_addr[15:8] == 8'hBC) ? next_byte :
        8'hFF; // Return 0xFF for all undocumented/test registers, as in MAME

    // Output assignments
    assign asic_valid = (state == UNLOCKED || state == PERM_UNLOCKED);  // Update to include PERM_UNLOCKED
    assign asic_status = status_reg;

endmodule 


