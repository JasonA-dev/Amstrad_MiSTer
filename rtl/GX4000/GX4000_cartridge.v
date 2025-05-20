module GX4000_cartridge
(
    input         clk_sys,
    input         reset,
    input         plus_mode,      // Plus mode input
    
    // Cartridge interface
    output [24:0] cart_addr,
    output  [7:0] cart_data,
    input         cart_rd,
    output        cart_wr,
    
    // ROM loading interface
    input         ioctl_wr,
    input  [24:0] ioctl_addr,
    input   [7:0] ioctl_dout,
    input         ioctl_download,
    input   [7:0] ioctl_index,  // Index to distinguish between CPR and BIN
    
    // Memory interface
    output [22:0] rom_addr,
    output  [7:0] rom_data,
    output reg    rom_wr,
    output        rom_rd,
    input   [7:0] rom_q,
    
    // Auto-boot interface
    output        auto_boot,
    output [15:0] boot_addr,
    
    // Plus ROM validation outputs
    output reg    plus_bios_valid,
    output reg [15:0] plus_bios_checksum,
    output reg [7:0]  plus_bios_version,
    
    // ROM information outputs
    output reg [7:0]  rom_type,
    output reg [15:0] rom_size,
    output reg [15:0] rom_checksum,
    output reg [7:0]  rom_version,
    output reg [31:0] rom_date,
    output reg [63:0] rom_title
);

// Memory map constants
localparam ROM_BASE = 23'h000000;  // ROM starts at 0
localparam BANK_SIZE = 16384;      // 16KB banks
localparam MAX_BLOCK_SIZE = 16384; // Maximum size of a cartridge block

// RIFF format constants (little-endian)
localparam RIFF_SIG = 32'h46464952;  // "RIFF" in little-endian
localparam AMS_SIG = 32'h414d5321;   // "Ams!" in little-endian
localparam FMT_SIG = 32'h666d7420;   // "fmt " in little-endian
localparam CB_PREFIX = 24'h6362;   // "cb" in little-endian

// State machine states
localparam 
    S_WAIT = 0,      // Wait for download
    S_HEADER = 1,    // Process RIFF header
    S_SIZE = 2,      // Get RIFF size
    S_FORM = 3,      // Check form type
    S_CHUNK = 4,     // Process chunks
    S_DATA = 5;      // Handle data

// Core registers
reg [2:0]  state;
reg [31:0] header;
reg [31:0] size;
reg [31:0] chunk_id;
reg [31:0] chunk_size;
reg [31:0] bytes_read;
reg [7:0]  bank;
reg [3:0]  retry_count;
reg [4:0]  current_block;  // Current cartridge block number (0-31)
reg [31:0] block_base;     // Base address for current block
reg [31:0] block_offset;   // Current offset within block
reg        filling_zeros;  // Flag to indicate we're filling remaining space with zeros

// Format chunk data
reg [7:0]  version;
reg [7:0]  flags;
reg [15:0] load_addr;
reg [15:0] exec_addr;

// Control registers
reg [22:0] addr;
reg [7:0]  data;
reg        auto_boot_en;
reg [15:0] boot_vector;

// Download state tracking
reg [2:0]  byte_count;
wire       is_cpr = (ioctl_index == 5);  // Make combinational to catch first byte
reg        valid_header;

// Debug counters and tracking
reg [31:0] total_bytes;
reg [31:0] valid_bytes;
reg [31:0] last_addr;

// Add protection challenge detection registers
reg [7:0] protection_state;
reg [7:0] protection_sequence[0:15];  // Store last 16 bytes of protection sequence
reg [3:0] protection_index;
reg protection_active;

// Protection challenge patterns
localparam [7:0] PROTECTION_PATTERN_1 = 8'h88;  // Common protection pattern
localparam [7:0] PROTECTION_PATTERN_2 = 8'h00;  // Another common pattern

// Protection state machine states
localparam 
    P_IDLE = 0,
    P_DETECTING = 1,
    P_CHALLENGE = 2,
    P_RESPONSE = 3;

// Main state machine
always @(posedge clk_sys) begin
    if (reset) begin
        state <= S_WAIT;
        retry_count <= 0;
        rom_wr <= 0;  // Default state
        total_bytes <= 0;
        valid_bytes <= 0;
        last_addr <= 0;
        header <= 0;
        byte_count <= 0;
        block_offset <= 0;
        filling_zeros <= 0;
        plus_bios_valid <= 0;  // Initialize to invalid
        protection_state <= P_IDLE;
        protection_index <= 0;
        protection_active <= 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            protection_sequence[i] <= 0;
        end
    end
    if (ioctl_download && ioctl_wr && is_cpr) begin
        rom_wr <= 0;  // Default state
        
        // Track total bytes
        total_bytes <= total_bytes + 1;
        
        case (state)
            S_WAIT: begin
                // Build RIFF signature (little-endian)
                header <= {ioctl_dout, header[31:8]};
                byte_count <= byte_count + 1;
                
                // Debug each byte of signature
                $display("DEBUG: RIFF check - byte %d = %h ('%c'), building: %h", 
                        byte_count, ioctl_dout, ioctl_dout,
                        {ioctl_dout, header[31:8]});
                
                if (byte_count == 3) begin
                    reg [31:0] sig = {ioctl_dout, header[31:8]};
                    $display("DEBUG: Checking RIFF signature %h against expected %h", sig, RIFF_SIG);
                    if (sig == RIFF_SIG) begin
                        state <= S_SIZE;
                        byte_count <= 0;
                        size <= 0;
                        $display("DEBUG: Found RIFF signature!");
                    end else begin
                        byte_count <= 0;
                        header <= 0;
                        $display("DEBUG: Invalid RIFF signature");
                    end
                end
            end

            S_SIZE: begin
                // Get file size (little-endian)
                size <= {ioctl_dout, size[31:8]};
                byte_count <= byte_count + 1;
                
                if (byte_count == 3) begin
                    $display("DEBUG: File size: %d bytes", {ioctl_dout, size[31:8]});
                    state <= S_FORM;
                    byte_count <= 0;
                    header <= 0;
                end
            end

            S_FORM: begin
                // Check for "Ams!" signature
                header <= {header[23:0], ioctl_dout};
                byte_count <= byte_count + 1;
                
                // Debug each byte of signature
                $display("DEBUG: Form check - byte %d = %h ('%c'), building: %h", 
                        byte_count, ioctl_dout, ioctl_dout,
                        {header[23:0], ioctl_dout});
                
                if (byte_count == 3) begin
                    reg [31:0] sig = {header[23:0], ioctl_dout};
                    $display("DEBUG: Checking form signature %h against expected %h", sig, AMS_SIG);
                    if (sig == AMS_SIG) begin
                        state <= S_CHUNK;
                        byte_count <= 0;
                        chunk_id <= 0;
                        valid_header <= 1;
                        retry_count <= 0;  // Reset retry counter on success
                        plus_bios_valid <= 1;  // Set valid when we have a valid AMS signature
                        $display("DEBUG: Found AMS signature! Setting plus_bios_valid=1");
                    end else begin
                        // Increment retry counter and check limit
                        retry_count <= retry_count + 1;
                        if (retry_count >= 4'h8) begin
                            // Too many retries, reset to WAIT state
                            state <= S_WAIT;
                            byte_count <= 0;
                            header <= 0;
                            $display("DEBUG: Form signature validation failed after 8 retries");
                        end else begin
                            // Stay in current state but reset byte counter
                            byte_count <= 0;
                            header <= 0;
                            $display("DEBUG: Invalid form signature, retry %d", retry_count + 1);
                        end
                    end
                end
            end

            S_CHUNK: begin
                // Process chunk header
                chunk_id <= {chunk_id[23:0], ioctl_dout};
                byte_count <= byte_count + 1;
                
                // Debug each byte of chunk ID
                $display("DEBUG: Chunk ID - byte %d = %h ('%c'), building: %h", 
                        byte_count, ioctl_dout, ioctl_dout,
                        {chunk_id[23:0], ioctl_dout});
                
                if (byte_count == 3) begin
                    reg [31:0] id = {chunk_id[23:0], ioctl_dout};
                    reg [15:0] prefix = id[31:16];  // Get 16-bit prefix
                    reg [7:0]  block_num = id[7:0];
                    
                    if (id == FMT_SIG) begin
                        $display("DEBUG: Found format chunk - ID=%h", id);
                        state <= S_DATA;
                        byte_count <= 0;
                        chunk_size <= 0;
                        bytes_read <= 0;
                    end
                    else if (prefix == CB_PREFIX) begin  // Check for "cb" prefix (16-bit)
                        // Handle all cartridge blocks (0-31)
                        if (block_num >= 8'h30 && block_num <= 8'h39) begin
                            // Calculate block number based on prefix and digit
                            reg [4:0] block_num_dec;
                            reg [7:0] prefix_num = id[15:8] - 8'h30;  // Get prefix digit from id[15:8]
                            
                            // Calculate block number: (prefix_num * 10) + digit
                            block_num_dec = (prefix_num * 10) + (block_num - 8'h30);
                            
                            // Only process if block number is valid (0-31)
                            if (block_num_dec <= 31) begin
                                current_block <= block_num_dec;
                                block_base <= block_num_dec * BANK_SIZE;
                                $display("DEBUG: Found cartridge block %d, base addr=%h", 
                                        block_num_dec, block_num_dec * BANK_SIZE);
                                state <= S_DATA;
                                byte_count <= 0;
                                chunk_size <= 0;
                                bytes_read <= 0;
                            end else begin
                                $display("DEBUG: Block number %d exceeds maximum (31)", block_num_dec);
                                state <= S_CHUNK;
                                byte_count <= 0;
                                chunk_id <= 0;
                            end
                        end
                        else begin
                            $display("DEBUG: Invalid block number %h in cartridge chunk", block_num);
                            state <= S_CHUNK;
                            byte_count <= 0;
                            chunk_id <= 0;
                        end
                    end
                    else begin
                        // Unknown chunk - skip to next chunk header
                        $display("DEBUG: Unknown chunk ID %h (prefix=%h, block=%h), searching for next valid chunk", 
                                id, prefix, block_num);
                        state <= S_CHUNK;
                        byte_count <= 0;
                        chunk_id <= 0;
                    end
                end
            end

            S_DATA: begin
                if (bytes_read == 0) begin
                    // First 4 bytes are chunk size (little-endian)
                    chunk_size <= {chunk_size[23:0], ioctl_dout};
                    byte_count <= byte_count + 1;
                    block_offset <= 0;  // Reset block offset at start of chunk
                    filling_zeros <= 0;  // Reset zero filling flag
                    
                    if (byte_count == 3) begin
                        reg [31:0] size = {chunk_size[23:0], ioctl_dout};
                        $display("DEBUG: Processing chunk of size %h bytes", size);
                        
                        if (size == 0) begin
                            // Skip zero-size chunks and look for next signature
                            $display("DEBUG: Skipping zero-size chunk, searching for next chunk");
                            state <= S_CHUNK;
                            byte_count <= 0;
                            chunk_id <= 0;
                        end else begin
                            // For cartridge blocks, limit size to 16KB
                            if (chunk_id[31:16] == CB_PREFIX) begin
                                if (size > MAX_BLOCK_SIZE) begin
                                    $display("DEBUG: Warning - Block %d size %h exceeds 16KB, limiting to %h bytes",
                                            current_block, size, MAX_BLOCK_SIZE);
                                    chunk_size <= MAX_BLOCK_SIZE;
                                end else if (size < MAX_BLOCK_SIZE) begin
                                    $display("DEBUG: Note - Block %d size %h is less than 16KB, will zero-fill to %h bytes",
                                            current_block, size, MAX_BLOCK_SIZE);
                                end
                            end
                            bytes_read <= 1;
                            byte_count <= 0;
                        end
                    end
                end
                else begin
                    // Process chunk data
                    bytes_read <= bytes_read + 1;
                    valid_bytes <= valid_bytes + 1;
                    
                    case (chunk_id)
                        FMT_SIG: begin
                            $display("DEBUG: Processing format chunk data - byte %d of %d", bytes_read, chunk_size);
                            case (bytes_read)
                                1: begin
                                    version <= ioctl_dout;
                                    plus_bios_version <= ioctl_dout;  // Store version
                                    $display("DEBUG: Format version: %h", ioctl_dout);
                                end
                                2: begin
                                    flags <= ioctl_dout;
                                    $display("DEBUG: Format flags: %h", ioctl_dout);
                                end
                                3: begin
                                    load_addr[7:0] <= ioctl_dout;
                                    $display("DEBUG: Load address low byte: %h", ioctl_dout);
                                end
                                4: begin
                                    load_addr[15:8] <= ioctl_dout;
                                    plus_bios_checksum <= {ioctl_dout, load_addr[7:0]};  // Store checksum
                                    $display("DEBUG: Load address: %h", {ioctl_dout, load_addr[7:0]});
                                end
                                5: begin
                                    exec_addr[7:0] <= ioctl_dout;
                                    $display("DEBUG: Exec address low byte: %h", ioctl_dout);
                                end
                                6: begin
                                    exec_addr[15:8] <= ioctl_dout;
                                    $display("DEBUG: Exec address: %h", {ioctl_dout, exec_addr[7:0]});
                                    if ({ioctl_dout, exec_addr[7:0]} != 16'h0000) begin
                                        auto_boot_en <= 1;
                                        boot_vector <= {ioctl_dout, exec_addr[7:0]};
                                        plus_bios_valid <= 1;  // Set valid when we have a valid exec address
                                        $display("DEBUG: Setting plus_bios_valid=1, exec_addr=%h", {ioctl_dout, exec_addr[7:0]});
                                    end else begin
                                        $display("DEBUG: Not setting plus_bios_valid - exec_addr is 0");
                                    end
                                end
                                default: begin
                                    if (bytes_read >= chunk_size) begin
                                        state <= S_CHUNK;
                                        $display("DEBUG: Format chunk complete - plus_bios_valid=%b", plus_bios_valid);
                                    end
                                end
                            endcase
                        end
                        
                        default: begin
                            // Check if this is a cartridge block (cb0X)
                            if (chunk_id[31:16] == CB_PREFIX) begin
                                // Calculate address
                                reg [31:0] block_addr = block_base + block_offset;
                                
                                // Handle data writing or zero filling
                                if (!filling_zeros && block_offset < chunk_size) begin
                                    // Still writing actual data
                                    if (block_offset < MAX_BLOCK_SIZE) begin
                                        addr <= block_addr[22:0];  // Map to 23-bit SDRAM address
                                        data <= ioctl_dout;
                                        block_offset <= block_offset + 1;
                                        
                                        // Track progress
                                        if ((block_offset & 16'hFFF) == 0) begin
                                            $display("DEBUG: Block %2d: %5d/%5d bytes written (SDRAM addr=%h)", 
                                                    current_block, block_offset + 1, 
                                                    (chunk_size > MAX_BLOCK_SIZE) ? MAX_BLOCK_SIZE : chunk_size,
                                                    block_addr);
                                        end
                                    end
                                    
                                    // Check if we need to start zero filling
                                    if (block_offset >= chunk_size - 1) begin
                                        if (chunk_size < MAX_BLOCK_SIZE) begin
                                            filling_zeros <= 1;
                                            $display("DEBUG: Starting zero-fill for block %d from offset %h (SDRAM addr=%h)", 
                                                    current_block, chunk_size, block_base + chunk_size);
                                        end else begin
                                            state <= S_CHUNK;
                                            $display("DEBUG: Block %2d complete: %5d bytes written to SDRAM base addr %h", 
                                                    current_block, chunk_size, block_base);
                                        end
                                    end
                                end
                                else if (filling_zeros) begin
                                    // Fill remaining space with zeros
                                    if (block_offset < MAX_BLOCK_SIZE) begin
                                        addr <= block_addr[22:0];  // Map to 23-bit SDRAM address
                                        data <= 8'h00;
                                        block_offset <= block_offset + 1;
                                        
                                        // Track zero-filling progress
                                        if ((block_offset & 16'hFFF) == 0) begin
                                            $display("DEBUG: Block %2d: zero-filling %5d/%5d (SDRAM addr=%h)", 
                                                    current_block, block_offset + 1, MAX_BLOCK_SIZE,
                                                    block_addr);
                                        end
                                    end
                                    
                                    // Check if zero filling is complete
                                    if (block_offset >= MAX_BLOCK_SIZE - 1) begin
                                        state <= S_CHUNK;
                                        $display("DEBUG: Block %2d complete: %5d bytes written + %5d bytes zero-filled to SDRAM base addr %h", 
                                                current_block, chunk_size, MAX_BLOCK_SIZE - chunk_size, block_base);
                                    end
                                end
                            end
                            // Skip unknown chunks
                            else if (bytes_read >= chunk_size) begin
                                $display("DEBUG: Skipped %d bytes of unknown chunk", bytes_read);
                                state <= S_CHUNK;
                            end
                        end
                    endcase
                end
            end
        endcase
    end

    // Add protection challenge detection logic
    if (reset) begin
        protection_state <= P_IDLE;
        protection_index <= 0;
        protection_active <= 0;
        for (integer i = 0; i < 16; i = i + 1) begin
            protection_sequence[i] <= 0;
        end
    end else begin
        // Monitor ROM reads for protection patterns
        if (rom_rd && !protection_active) begin
            // Store read data in sequence buffer
            protection_sequence[protection_index] <= rom_q;
            protection_index <= protection_index + 1;
            
            // Check for protection patterns
            if (rom_q == PROTECTION_PATTERN_1 || rom_q == PROTECTION_PATTERN_2) begin
                protection_state <= P_DETECTING;
                $display("[ACID] Protection pattern detected: %h", rom_q);
            end
        end
/*
        // Monitor CRTC register access
        if (cart_addr[15:8] == 8'hBC) begin
            reg [7:0] reg_num = cart_addr[7:0];
            case (reg_num)
                8'h00: $display("[ACID] CRTC: R0 (Horizontal Total) = %h", cart_data);
                8'h01: $display("[ACID] CRTC: R1 (Horizontal Displayed) = %h", cart_data);
                8'h02: $display("[ACID] CRTC: R2 (Horizontal Sync Position) = %h", cart_data);
                8'h03: $display("[ACID] CRTC: R3 (Sync Widths) = %h", cart_data);
                8'h04: $display("[ACID] CRTC: R4 (Vertical Total) = %h", cart_data);
                8'h05: $display("[ACID] CRTC: R5 (Vertical Total Adjust) = %h", cart_data);
                8'h06: $display("[ACID] CRTC: R6 (Vertical Displayed) = %h", cart_data);
                8'h07: $display("[ACID] CRTC: R7 (Vertical Sync Position) = %h", cart_data);
                8'h08: $display("[ACID] CRTC: R8 (Interlace & Skew) = %h", cart_data);
                8'h09: $display("[ACID] CRTC: R9 (Maximum Raster) = %h", cart_data);
                8'h0A: $display("[ACID] CRTC: R10 (Cursor Start) = %h", cart_data);
                8'h0B: $display("[ACID] CRTC: R11 (Cursor End) = %h", cart_data);
                8'h0C: $display("[ACID] CRTC: R12 (Start Address High) = %h", cart_data);
                8'h0D: $display("[ACID] CRTC: R13 (Start Address Low) = %h", cart_data);
                8'h0E: $display("[ACID] CRTC: R14 (Cursor Address High) = %h", cart_data);
                8'h0F: $display("[ACID] CRTC: R15 (Cursor Address Low) = %h", cart_data);
                8'h10: $display("[ACID] CRTC: R16 (Light Pen High) = %h", cart_data);
                8'h11: $display("[ACID] CRTC: R17 (Light Pen Low) = %h", cart_data);
                default: $display("[ACID] CRTC: Unknown register %h = %h", reg_num, cart_data);
            endcase
        end
  */   
        // Protection state machine
        case (protection_state)
            P_IDLE: begin
                // Wait for protection pattern
            end
            
            P_DETECTING: begin
                // Monitor for challenge sequence
                if (protection_index >= 4) begin  // Need at least 4 bytes for challenge
                    // Check for known challenge patterns
                    if (protection_sequence[0] == PROTECTION_PATTERN_1 &&
                        protection_sequence[1] == PROTECTION_PATTERN_2) begin
                        protection_state <= P_CHALLENGE;
                        protection_active <= 1;
                        $display("[ACID] Protection challenge detected! Pattern: %h %h", 
                                protection_sequence[0], protection_sequence[1]);
                    end else begin
                        protection_state <= P_IDLE;
                        $display("[ACID] Invalid protection pattern: %h %h", 
                                protection_sequence[0], protection_sequence[1]);
                    end
                end
            end
            
            P_CHALLENGE: begin
                // Monitor for challenge completion
                if (protection_index >= 8) begin  // Full challenge sequence
                    protection_state <= P_RESPONSE;
                    $display("[ACID] Protection challenge sequence: %h %h %h %h %h %h %h %h",
                            protection_sequence[0], protection_sequence[1],
                            protection_sequence[2], protection_sequence[3],
                            protection_sequence[4], protection_sequence[5],
                            protection_sequence[6], protection_sequence[7]);
                end
            end
            
            P_RESPONSE: begin
                // Monitor for response sequence
                if (protection_index >= 12) begin  // Full response sequence
                    protection_state <= P_IDLE;
                    protection_active <= 0;
                    protection_index <= 0;
                    $display("[ACID] Protection response sequence: %h %h %h %h",
                            protection_sequence[8], protection_sequence[9],
                            protection_sequence[10], protection_sequence[11]);
                    $display("[ACID] Unlock sequence complete - checking validity");
                end
            end
        endcase
    end
end

// Bank register access
always @(posedge clk_sys) begin
    if (reset) begin
        bank <= 0;
    end
    else if (plus_mode && cart_wr && cart_addr[24:8] == 17'h7000) begin
        case (cart_addr[7:0])
            8'h00: bank <= cart_data;
            8'h01: auto_boot_en <= cart_data[0];
            8'h02: boot_vector[7:0] <= cart_data;
            8'h03: boot_vector[15:8] <= cart_data;
        endcase
    end
end

// Output assignments
assign rom_addr = addr;  // Keep using internal addr for now
assign rom_data = data;  // Keep using internal data
assign rom_rd = plus_mode && cart_rd;
assign auto_boot = auto_boot_en;
assign boot_addr = boot_vector;

// Drive cartridge interface signals - only enable during cartridge block writes
assign cart_addr = {2'b00, addr};  // Extend to 25 bits
assign cart_data = data;
assign cart_wr = ioctl_download && ioctl_wr && is_cpr && 
                 (state == S_DATA) && (chunk_id[31:16] == CB_PREFIX) &&
                 (bytes_read > 0) && (block_offset < MAX_BLOCK_SIZE);

endmodule 