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
    
    // Hardware register inputs
    input   [7:0] sprite_control,    // Sprite control register
    input   [7:0] sprite_collision,  // Sprite collision register
    input   [7:0] audio_control,     // Audio control register
    input   [7:0] audio_status,      // Audio status register
    input   [7:0] video_status,      // Video status register
    
    // I/O hardware inputs
    input   [7:0] joy1_data,         // Joystick 1 data
    input   [7:0] joy2_data,         // Joystick 2 data
    input         joy_swap,          // Joystick swap flag
    input   [7:0] io_status,         // I/O status register
    input   [7:0] io_control,        // I/O control register
    input   [7:0] io_data,           // I/O data register
    input   [7:0] io_direction,      // I/O direction register
    input   [7:0] io_interrupt,      // I/O interrupt register
    input   [7:0] io_timer,          // I/O timer register
    input   [7:0] io_clock,          // I/O clock register
    
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
    reg [7:0] io_register;
    reg [7:0] io_register_index;

    // 16KB ASIC RAM window (0x4000–0x7FFF)
    reg [7:0] asic_ram [0:16383];

    // RAM read data
    reg [7:0] asic_ram_data;
    reg [7:0] asic_ram_q_reg;

    // RAM read/write logic
    always @(posedge clk_sys) begin
        if (reset) begin
            // Optionally clear RAM on reset
            // integer i;
            // for (i = 0; i < 16384; i = i + 1) asic_ram[i] <= 8'h00;
        end else if (plus_mode) begin
            // Write to ASIC RAM from CPU
            if (cpu_wr && (cpu_addr >= 16'h4000) && (cpu_addr <= 16'h7FFF)) begin
                $display("[ACID] 22 ASIC RAM Write: addr=%h data=%h", cpu_addr, cpu_data_in);
                asic_ram[cpu_addr - 16'h4000] <= cpu_data_in;
            end
            // Write to ASIC RAM from external port
            if (asic_ram_wr) begin
                asic_ram[asic_ram_addr] <= asic_ram_din;
            end
            // Read from ASIC RAM for CPU
            if (cpu_rd && (cpu_addr >= 16'h4000) && (cpu_addr <= 16'h7FFF)) begin
                asic_ram_data <= asic_ram[cpu_addr - 16'h4000];
            end
            // Read from ASIC RAM for external port
            if (asic_ram_rd) begin
                asic_ram_q_reg <= asic_ram[asic_ram_addr];
            end
        end
    end

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
                8'h05: asic_register <= 8'h00;          // Reserved
                8'h06: asic_register <= 8'h00;          // Reserved
                8'h07: asic_register <= 8'h00;          // Reserved
                default: asic_register <= 8'h00;         // Return 0 for other reads
            endcase
        end
    end

    // Sequential register reading for I/O port range (0x7F00-0x7FFF)
    always @(posedge clk_sys) begin
        if (reset) begin
            io_register_index <= 8'h00;
            io_register <= 8'h00;
        end else if (plus_mode && cpu_rd && (cpu_addr >= 16'h7F00) && (cpu_addr <= 16'h7FFF)) begin
            // Increment register index on each read
            io_register_index <= io_register_index + 1'd1;
            
            // Return different register values based on index
            case (io_register_index)
                8'h00: io_register <= joy1_data;        // Joystick 1 data
                8'h01: io_register <= joy2_data;        // Joystick 2 data
                8'h02: io_register <= {7'h00, joy_swap};// Joystick swap flag
                8'h03: io_register <= io_status;        // I/O status register
                8'h04: io_register <= io_control;       // I/O control register
                8'h05: io_register <= io_data;          // I/O data register
                8'h06: io_register <= io_direction;     // I/O direction register
                8'h07: io_register <= io_interrupt;     // I/O interrupt register
                8'h08: io_register <= io_timer;         // I/O timer register
                8'h09: io_register <= io_clock;         // I/O clock register
                default: io_register <= 8'h00;          // Return 0 for other reads
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
                if (state == PERM_UNLOCKED) begin
                    // Ignore all writes, stay permanently unlocked
                end else begin
                    // Accept both per-address, fixed-address, and BC10-only unlock sequences
                    if (state == LOCKED && seq_index == 0) begin
                        unlock_addr <= cpu_addr[7:0];
                    end
                    // Check if this is part of the unlock sequence
                    if (
                        (cpu_addr[7:0] == cpu_data_in) || // per-address
                        (cpu_addr[7:0] == unlock_addr && cpu_data_in == UNLOCK_SEQ[seq_index]) || // fixed-address
                        (cpu_addr[7:0] == 8'h00 && cpu_data_in == UNLOCK_SEQ[seq_index]) || // BC00-only
                        (cpu_addr[7:0] == 8'h10 && cpu_data_in == UNLOCK_SEQ[seq_index])    // BC10-only edge case
                    ) begin
                        $display("[ACID] Unlock write: BC%02X = %h (matches address or fixed or BC10-only)", 
                                cpu_addr[7:0], cpu_data_in);
                        // Process as part of unlock sequence
                        case (state)
                            LOCKED: begin
                                if (cpu_data_in == UNLOCK_SEQ[0]) begin
                                    state <= UNLOCKING;
                                    seq_index <= 1;
                                    received_seq[0] <= cpu_data_in;
                                    $display("[ACID] Unlock started (fixed, per-address, or BC10-only)");
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
    end

    // Output assignment based on address range
    assign cpu_data_out = 
        (cpu_addr >= 16'h4000 && cpu_addr <= 16'h7FFF) ? asic_ram_data :
        ((cpu_addr >= 16'h7F00 && cpu_addr <= 16'h7FFF) || (cpu_addr >= 16'hDF00 && cpu_addr <= 16'hDFFF)) ? io_register :
        (cpu_addr[15:8] == 8'hBC) ? next_byte :
        8'h00;

    // Output assignments
    assign asic_valid = (state == UNLOCKED || state == PERM_UNLOCKED);  // Update to include PERM_UNLOCKED
    assign asic_status = status_reg;
    assign asic_ram_q = asic_ram_q_reg;

endmodule 


