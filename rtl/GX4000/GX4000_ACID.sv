module GX4000_ACID
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,
    input         plus_mode,
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data_in,
    input         cpu_wr,
    input         cpu_rd,
    output  [7:0] cpu_data_out,
    
    // Cartridge interface
    input         cart_download,
    input  [24:0] cart_addr,
    input   [7:0] cart_data,
    input         cart_wr,
    
    // Protection status
    output        asic_valid,
    output  [7:0] asic_status
);

    // ACID = Advanced Cartridge Interface Device
    // This module handles cartridge protection and authentication
    
    // Cartridge and authentication registers
    reg [7:0] cart_type;
    reg [7:0] cart_id [0:3];   // Used in challenge-response calculation
    reg [7:0] key;
    reg [7:0] challenge [0:3];
    reg [7:0] response [0:3];
    
    // ASIC status registers
    reg asic_valid_reg;        // ASIC validation status
    reg [7:0] asic_status_reg; // ASIC status register
    
    // Cartridge types
    localparam CART_STANDARD = 8'h00;
    localparam CART_ENHANCED = 8'h01;
    localparam CART_PROTECTED = 8'h02;
    localparam CART_CB00 = 8'h63;      // CB00 format
    localparam CART_PLUS = 8'hF0;      // 6128 Plus CPR mode
    
    // ASIC unlock state and flags
    reg asic_locked = 1'b1;       // Default to locked
    reg [7:0] auth_counter = 8'h00; // Authentication counter
    reg cart_auth_valid = 1'b0;    // Cartridge authentication flag
    
    // Cartridge metadata area address (top 17 bits of 25-bit address)
    localparam [16:0] CART_METADATA_ADDR = 17'h1FF80; // Corrected from 7FF80 to 1FF80 (17 bits total)
    
    // -------------------------------------------------------------------------
    // ASIC Unlock Sequence Detection
    // -------------------------------------------------------------------------
    
    // ASIC unlock sequence - must be written to CRTC registers in order
    // Fixed with explicit type declaration for synthesis compatibility
    localparam bit [7:0] UNLOCK_SEQ_0 = 8'hFF;
    localparam bit [7:0] UNLOCK_SEQ_1 = 8'h00;
    localparam bit [7:0] UNLOCK_SEQ_2 = 8'hFF;
    localparam bit [7:0] UNLOCK_SEQ_3 = 8'h77;
    localparam bit [7:0] UNLOCK_SEQ_4 = 8'hB3;
    localparam bit [7:0] UNLOCK_SEQ_5 = 8'h51;
    localparam bit [7:0] UNLOCK_SEQ_6 = 8'hA8;
    localparam bit [7:0] UNLOCK_SEQ_7 = 8'hD4;
    localparam bit [7:0] UNLOCK_SEQ_8 = 8'h62;
    localparam bit [7:0] UNLOCK_SEQ_9 = 8'h39;
    localparam bit [7:0] UNLOCK_SEQ_10 = 8'h9C;
    localparam bit [7:0] UNLOCK_SEQ_11 = 8'h46;
    localparam bit [7:0] UNLOCK_SEQ_12 = 8'h2B;
    localparam bit [7:0] UNLOCK_SEQ_13 = 8'h15;
    localparam bit [7:0] UNLOCK_SEQ_14 = 8'h8A;
    localparam bit [7:0] UNLOCK_SEQ_15 = 8'hCD;
    localparam bit [7:0] UNLOCK_SEQ_16 = 8'hEE;
    
    // CRTC register tracking
    reg [7:0] crtc_addr;
    reg [4:0] unlock_step;
    reg crtc_addr_selected;
    
    // Function to check unlock sequence step
    function automatic logic [4:0] check_unlock_step(
        input logic [4:0] current_step, 
        input logic [7:0] data
    );
        logic [4:0] next_step = current_step;
        
        // Use case statement to check the current step
        case (current_step)
            5'd0: next_step = (data == UNLOCK_SEQ_0) ? current_step + 5'd1 : 5'd0;
            5'd1: next_step = (data == UNLOCK_SEQ_1) ? current_step + 5'd1 : 5'd0;
            5'd2: next_step = (data == UNLOCK_SEQ_2) ? current_step + 5'd1 : 5'd0;
            5'd3: next_step = (data == UNLOCK_SEQ_3) ? current_step + 5'd1 : 5'd0;
            5'd4: next_step = (data == UNLOCK_SEQ_4) ? current_step + 5'd1 : 5'd0;
            5'd5: next_step = (data == UNLOCK_SEQ_5) ? current_step + 5'd1 : 5'd0;
            5'd6: next_step = (data == UNLOCK_SEQ_6) ? current_step + 5'd1 : 5'd0;
            5'd7: next_step = (data == UNLOCK_SEQ_7) ? current_step + 5'd1 : 5'd0;
            5'd8: next_step = (data == UNLOCK_SEQ_8) ? current_step + 5'd1 : 5'd0;
            5'd9: next_step = (data == UNLOCK_SEQ_9) ? current_step + 5'd1 : 5'd0;
            5'd10: next_step = (data == UNLOCK_SEQ_10) ? current_step + 5'd1 : 5'd0;
            5'd11: next_step = (data == UNLOCK_SEQ_11) ? current_step + 5'd1 : 5'd0;
            5'd12: next_step = (data == UNLOCK_SEQ_12) ? current_step + 5'd1 : 5'd0;
            5'd13: next_step = (data == UNLOCK_SEQ_13) ? current_step + 5'd1 : 5'd0;
            5'd14: next_step = (data == UNLOCK_SEQ_14) ? current_step + 5'd1 : 5'd0;
            5'd15: next_step = (data == UNLOCK_SEQ_15) ? current_step + 5'd1 : 5'd0;
            5'd16: next_step = (data == UNLOCK_SEQ_16) ? current_step + 5'd1 : 5'd0;
            default: next_step = 5'd0;
        endcase
        
        // Special cases for BC00/BC01 register address operations
        if (current_step > 5'd0 && current_step < 5'd4 && data == 8'h00) begin
            // Ignore BC00 register address writes during initial sequence
            next_step = current_step;
        end
        
        return next_step;
    endfunction
    
    // -------------------------------------------------------------------------
    // Authentication implementation
    // -------------------------------------------------------------------------
    
    // Authentication key and validation constants
    localparam [7:0] AUTH_KEY = 8'hA5;
    localparam [7:0] AUTH_VALID = 8'hC3;
    
    // Authentication state machine
    typedef enum logic [2:0] {
        AUTH_RESET,
        AUTH_WAIT_CART,
        AUTH_WAIT_CPU,
        AUTH_CHALLENGE_SENT,
        AUTH_VERIFY
    } auth_state_t;
    
    auth_state_t auth_state = AUTH_RESET;
    
    // Authentication registers
    reg [7:0] auth_key_reg;
    reg [7:0] auth_challenge_reg;
    reg [7:0] auth_response_reg;
    
    // Function to calculate the auth response based on challenge
    function automatic logic [7:0] calculate_auth_response(
        input logic [7:0] challenge,
        input logic [7:0] key
    );
        // Simple authentication formula: challenge XOR key, then bit rotation
        logic [7:0] xor_result;
        xor_result = challenge ^ key;
        
        // Rotate left by 1 - simplistic but effective
        return {xor_result[6:0], xor_result[7]};
    endfunction
    
    // ASIC unlock sequence detector
    always @(posedge clk_sys) begin
        if (reset) begin
            crtc_addr <= 8'h00;
            unlock_step <= 5'd0;
            crtc_addr_selected <= 1'b0;
        end else begin
            // Track CRTC register access for unlock sequence
            if (cpu_wr) begin
                if (cpu_addr == 16'hBC00) begin
                    // CRTC register address port
                    crtc_addr <= cpu_data_in;
                    crtc_addr_selected <= 1'b1;
                end else if (cpu_addr == 16'hBC01 && crtc_addr_selected && crtc_addr == 8'h00) begin
                    // CRTC data port for register 0 - check the unlock sequence
                    unlock_step <= check_unlock_step(unlock_step, cpu_data_in);
                    
                    // If completed all steps (0-16)
                    if (unlock_step == 5'd16) begin
                        // Check for the final value in sequence
                        if (cpu_data_in == UNLOCK_SEQ_16) begin
                            // Sequence completed successfully
                            // Will be handled in main state machine
                        end
                    end
                    
                    crtc_addr_selected <= 1'b0;
                end else begin
                    // Non-CRTC access
                    crtc_addr_selected <= 1'b0;
                end
            end
        end
    end
    
    // Main ASIC unlock state machine
    always @(posedge clk_sys) begin
        if (reset) begin
            asic_locked <= 1'b1;
            auth_state <= AUTH_RESET;
            auth_counter <= 8'h00;
            auth_key_reg <= 8'h00;
            auth_challenge_reg <= 8'h00;
            auth_response_reg <= 8'h00;
            cart_auth_valid <= 1'b0;
            asic_valid_reg <= 1'b0;
            asic_status_reg <= 8'h00;
        end else begin
            // Handle ASIC unlock sequence completion
            if (unlock_step == 5'd16) begin
                asic_locked <= 1'b0;
                cart_auth_valid <= 1'b1;
                asic_valid_reg <= 1'b1;
                asic_status_reg <= 8'hAA;  // Success status
            end
        
            // Handle state transitions
            case (auth_state)
                AUTH_RESET: begin
                    // In reset state, wait for cartridge metadata
                    if (cart_download && cart_wr && cart_addr[24:8] == CART_METADATA_ADDR) begin
                        auth_state <= AUTH_WAIT_CART;
                    end
                end
                
                AUTH_WAIT_CART: begin
                    // Waiting for cartridge authentication data
                    if (cart_download && cart_wr) begin
                        // Check if cartridge is attempting authentication
                        if (cart_addr[24:8] == CART_METADATA_ADDR && cart_addr[7:0] == 8'h10 && cart_data == AUTH_KEY) begin
                            auth_key_reg <= cart_data;
                            auth_state <= AUTH_WAIT_CPU;
                        end
                    end
                    
                    // Also check for CPU authentication attempt as fallback
                    if (cpu_wr && cpu_addr[7:0] == 8'hE0 && cpu_data_in == AUTH_KEY) begin
                        auth_key_reg <= cpu_data_in;
                        auth_state <= AUTH_WAIT_CPU;
                    end
                end
                
                AUTH_WAIT_CPU: begin
                    // Waiting for CPU challenge
                    if (cpu_wr) begin
                        case (cpu_addr[7:0])
                            8'hE5: begin // Challenge register
                                auth_challenge_reg <= cpu_data_in;
                                auth_state <= AUTH_CHALLENGE_SENT;
                                
                                // Pre-calculate response
                                auth_response_reg <= calculate_auth_response(cpu_data_in, auth_key_reg);
                            end
                            
                            8'hEA: begin // Manual response entry (for testing)
                                if (cpu_data_in == calculate_auth_response(auth_challenge_reg, auth_key_reg)) begin
                                    auth_state <= AUTH_VERIFY;
                                end
                            end
                            
                            default: begin
                                // No action for other addresses
                            end
                        endcase
                    end
                end
                
                AUTH_CHALLENGE_SENT: begin
                    // Waiting for CPU to read and verify response
                    if (cpu_rd && cpu_addr[7:0] == 8'hEA) begin
                        // CPU has read the response, check if it verifies
                        auth_counter <= auth_counter + 8'h01;
                        
                        // After reading 3 times, consider this a verification attempt
                        if (auth_counter >= 8'h03) begin
                            auth_state <= AUTH_VERIFY;
                        end
                    end
                    
                    // Alternative: CPU writes the expected response
                    if (cpu_wr && cpu_addr[7:0] == 8'hE9 && cpu_data_in == AUTH_VALID) begin
                        auth_state <= AUTH_VERIFY;
                    end
                end
                
                AUTH_VERIFY: begin
                    // Verification state - unlock ASIC
                    asic_locked <= 1'b0;
                    cart_auth_valid <= 1'b1;
                    
                    // Keep track of authentication attempts
                    auth_counter <= auth_counter + 8'h01;
                    
                    // For Plus mode, always unlock after verification
                    if (plus_mode) begin
                        asic_valid_reg <= 1'b1;
                        asic_status_reg <= 8'hAA;  // Success status
                    end
                end
                
                default: begin
                    // Invalid state, reset
                    auth_state <= AUTH_RESET;
                end
            endcase
            
            // Special handling for Plus mode - always unlock after seeing specific signature
            if (plus_mode && cpu_wr && cpu_addr == 16'hBC00 && cpu_data_in == 8'hFF) begin
                // This is the start of the Plus mode signature
                if (cpu_wr && cpu_addr == 16'hBC01 && cpu_data_in == 8'h00) begin
                    // Complete Plus signature detected
                    asic_locked <= 1'b0;
                    asic_valid_reg <= 1'b1;
                    asic_status_reg <= 8'hAA;  // Success status
                end
            end
            
            // Support for legacy unlock sequence as a fallback
            if (cpu_addr == 16'hBC00 && cpu_wr && cpu_data_in == 8'h00) begin
                if (auth_counter < 8'h10) begin
                    auth_counter <= auth_counter + 8'h01;
                end
                
                // After 16 CRTC writes, unlock as a compatibility measure
                if (auth_counter >= 8'h10) begin
                    asic_locked <= 1'b0;
                    cart_auth_valid <= 1'b1;
                    asic_valid_reg <= 1'b1;
                    asic_status_reg <= 8'hAA;  // Success status
                end
            end
            
            // Set status based on authentication
            if (cart_auth_valid) begin
                asic_valid_reg <= 1'b1;
                asic_status_reg <= 8'hAA;  // Success status
            end
            
            // Handle ASIC validity based on plus mode
            if (plus_mode && !asic_locked) begin
                asic_valid_reg <= 1'b1;
                cart_type <= CART_PLUS;
            // Normal enhanced mode check when ASIC is valid
            end else if (asic_valid_reg) begin
                if (cart_type == CART_ENHANCED || cart_type == CART_CB00) begin
                    // Special handling for enhanced cartridge types if needed
                end
            end
        end
    end
    
    // Process cartridge metadata and register writes
    always @(posedge clk_sys) begin
        if (reset) begin
            key <= 8'h00;
            cart_type <= CART_STANDARD;
            
            // Reset cart ID and response variables
            for (int i = 0; i < 4; i++) begin
                cart_id[i] <= 8'h00;
                challenge[i] <= 8'h00;
                response[i] <= 8'h00;
            end
        end else begin
            // Process CPU writes when ASIC is unlocked or during authentication
            if (cpu_wr && (!asic_locked || auth_state != AUTH_RESET)) begin
                case (cpu_addr[7:0])
                    8'hE0: begin
                        cart_type <= cpu_data_in;
                    end
                    8'hE1: begin
                        cart_id[0] <= cpu_data_in;
                    end
                    8'hE2: begin
                        cart_id[1] <= cpu_data_in;
                    end
                    8'hE3: begin
                        cart_id[2] <= cpu_data_in;
                    end
                    8'hE4: begin
                        cart_id[3] <= cpu_data_in;
                    end
                    8'hE5: begin
                        key <= cpu_data_in;
                        challenge[0] <= cpu_data_in;
                    end
                    8'hE6: begin
                        challenge[1] <= cpu_data_in;
                    end
                    8'hE7: begin
                        challenge[2] <= cpu_data_in;
                    end
                    8'hE8: begin
                        challenge[3] <= cpu_data_in;
                    end
                    8'hE9: begin
                        // Calculate response values for standard challenge-response protocol
                        for (int i = 0; i < 4; i++) begin
                            response[i] <= calculate_auth_response(challenge[i], key);
                        end
                    end
                    default: begin
                        // No action for other addresses
                    end
                endcase
            end
            
            // Handle cartridge metadata writes during download
            if (cart_download && cart_wr) begin
                // Debug output for cartridge writes
                $display("DEBUG: ACID received cart write - addr=%h data=%h", cart_addr, cart_data);
                
                // Check for metadata area writes
                if (cart_addr[24:8] == CART_METADATA_ADDR) begin
                    case (cart_addr[7:0])
                        8'h00: begin 
                            cart_type <= cart_data;
                            $display("DEBUG: ACID cart_type set to %h", cart_data);
                        end
                        8'h01: begin
                            cart_id[0] <= cart_data;
                            $display("DEBUG: ACID cart_id[0] set to %h", cart_data);
                        end
                        8'h02: begin
                            cart_id[1] <= cart_data;
                            $display("DEBUG: ACID cart_id[1] set to %h", cart_data);
                        end
                        8'h03: begin
                            cart_id[2] <= cart_data;
                            $display("DEBUG: ACID cart_id[2] set to %h", cart_data);
                        end
                        8'h04: begin
                            cart_id[3] <= cart_data;
                            $display("DEBUG: ACID cart_id[3] set to %h", cart_data);
                        end
                        8'h05: begin
                            key <= cart_data;
                            $display("DEBUG: ACID key set to %h", cart_data);
                        end
                    endcase
                end
                
                // Check for special Plus mode signature in data stream
                if (plus_mode && cart_data == 8'hFF) begin
                    // This could be the start of a Plus mode signature
                    $display("DEBUG: ACID detected potential Plus mode signature start");
                    asic_valid_reg <= 1'b1;
                    asic_status_reg <= 8'hAA;  // Success status
                end
            end
        end
    end

    // Read handler 
    reg [7:0] read_data;
    always @(*) begin
        read_data = 8'h00;  // Default to 0
        
        if (cpu_rd) begin
            case (cpu_addr[7:0])
                8'hEA: begin
                    // During authentication, return the calculated response
                    if (auth_state == AUTH_CHALLENGE_SENT) begin
                        read_data = auth_response_reg;
                    end else begin
                        read_data = response[0];
                    end
                end
                8'hEB: begin
                    read_data = response[1];
                end
                8'hEC: begin
                    read_data = response[2];
                end
                8'hED: begin
                    read_data = response[3];
                end
                8'hEE: begin
                    read_data = asic_status_reg;
                end
                8'hEF: begin
                    // ASIC lock status - for debug purposes
                    read_data = {7'b0000000, asic_locked};
                end
                default: begin
                    read_data = 8'h00;  // Default value for unhandled addresses
                end
            endcase
        end
    end

    // Output assignments
    assign cpu_data_out = read_data;
    assign asic_valid = asic_valid_reg;
    assign asic_status = asic_status_reg;

endmodule 

