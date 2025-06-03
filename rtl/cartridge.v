module cartridge
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,  // GX4000 mode compatibility input
    input         plus_mode,    // Plus mode input
    
    // Cartridge interface
    input  [24:0] cart_addr,
    input   [7:0] cart_data,
    input         cart_rd,
    input         cart_wr,
    
    // ROM loading interface
    input         ioctl_wr,
    input  [24:0] ioctl_addr,
    input   [7:0] ioctl_dout,
    input         ioctl_download,
    input   [7:0] ioctl_index,  // Index to distinguish between CPR and BIN
    
    // Memory interface
    output [22:0] rom_addr,
    output  [7:0] rom_data,
    output        rom_wr,
    output        rom_rd,
    output  [7:0] rom_q,
    
    // Auto-boot interface
    output        auto_boot,
    output [15:0] boot_addr,
    
    // Cartridge information
    output reg [7:0] rom_type,
    output reg [15:0] rom_size,
    output reg [15:0] rom_checksum,
    output reg [7:0] rom_version,
    output reg [31:0] rom_date,
    output reg [63:0] rom_title,
    
    // Plus ROM validation outputs
    output reg plus_bios_valid,
    output reg [15:0] plus_bios_checksum,
    output reg [7:0] plus_bios_version
);

// Combine inputs for unified Plus mode
wire active_plus_mode = gx4000_mode | plus_mode;

// Internal registers
reg [7:0] rom_bank;
reg [7:0] rom_data_reg;
reg [22:0] rom_addr_reg;
reg auto_boot_reg;
reg [15:0] boot_addr_reg;

// ROM header registers
reg [7:0] header_state = 0;
reg header_valid = 0;
reg [7:0] header_data[0:31];
reg [31:0] riff_signature;
reg [31:0] ams_signature;

// ROM type definitions
localparam TYPE_STANDARD = 8'h00;
localparam TYPE_ENHANCED = 8'h01;
localparam TYPE_PROTECTED = 8'h02;
localparam TYPE_PLUS = 8'hF0;      // Plus mode ROM format

// Determine if current download is a CPR or BIN file
wire is_cpr_file = ioctl_index == 5;  // Index 5 = CPR files (Plus ROM)
wire is_bin_file = ioctl_index == 6;  // Index 6 = BIN files (Binary ROM)

// ROM bank selection
always @(posedge clk_sys) begin
    if (reset) begin
        rom_bank <= 8'h00;
        auto_boot_reg <= 0;
        boot_addr_reg <= 16'h0000;
    end else if (active_plus_mode && cart_wr && cart_addr[24:8] == 17'h7000) begin
        // Use the lower 8 bits as the register selection
        case (cart_addr[7:0])
            8'h00: rom_bank <= cart_data;
            8'h01: auto_boot_reg <= cart_data[0];
            8'h02: boot_addr_reg[7:0] <= cart_data;
            8'h03: boot_addr_reg[15:8] <= cart_data;
        endcase
    end
end

// ROM access
always @(posedge clk_sys) begin
    if (active_plus_mode && cart_rd) begin
        // Use the lower 15 bits of the address
        rom_addr_reg <= {rom_bank, cart_addr[14:0]};
        rom_data_reg <= cart_data;
    end
end

// ROM header processing
always @(posedge clk_sys) begin
    if (reset) begin
        header_state <= 0;
        header_valid <= 0;
        rom_type <= TYPE_STANDARD;
        rom_size <= 16'h0000;
        rom_checksum <= 16'h0000;
        rom_version <= 8'h00;
        rom_date <= 32'h00000000;
        rom_title <= 64'h0000000000000000;
        riff_signature <= 32'h0;
        ams_signature <= 32'h0;
        
        // Cartridge validation reset
        plus_bios_valid <= 0;
        plus_bios_checksum <= 0;
        plus_bios_version <= 0;
    end else if (ioctl_download && ioctl_wr) begin
        // Process headers for Plus ROM files
        if (is_cpr_file) begin
            case (header_state)
                0: begin
                    // Store header data
                    if (ioctl_addr < 32) begin
                        header_data[ioctl_addr[4:0]] <= ioctl_dout;
                    
                        // Build RIFF signature (first 4 bytes)
                        if (ioctl_addr < 4) begin
                            case (ioctl_addr)
                                0: riff_signature[31:24] <= ioctl_dout;
                                1: riff_signature[23:16] <= ioctl_dout;
                                2: riff_signature[15:8] <= ioctl_dout;
                                3: riff_signature[7:0] <= ioctl_dout;
                            endcase
                        end
                        // Build AMS! signature (bytes 8-11)
                        else if (ioctl_addr >= 8 && ioctl_addr < 12) begin
                            case (ioctl_addr)
                                8: ams_signature[31:24] <= ioctl_dout;
                                9: ams_signature[23:16] <= ioctl_dout;
                                10: ams_signature[15:8] <= ioctl_dout;
                                11: ams_signature[7:0] <= ioctl_dout;
                            endcase
                        end
                    
                        // Move to parsing state when header is complete
                        if (ioctl_addr == 31) begin
                            header_state <= 1;
                        end
                    end
                end
                1: begin
                    // Parse header data
                    if (riff_signature == 32'h52494646 && ams_signature == 32'h414D5321) begin
                        // Valid RIFF + AMS! signature
                        rom_type <= header_data[12];  // Type at offset 12
                        rom_size <= {header_data[14], header_data[13]};  // Size at offset 13-14
                        rom_checksum <= {header_data[16], header_data[15]};  // Checksum at offset 15-16
                        rom_version <= header_data[17];  // Version at offset 17
                        rom_date <= {header_data[21], header_data[20], header_data[19], header_data[18]};  // Date at offset 18-21
                        rom_title <= {
                            header_data[29], header_data[28], header_data[27], header_data[26],
                            header_data[25], header_data[24], header_data[23], header_data[22]
                        };  // Title at offset 22-29
                        header_valid <= 1;
                        
                        // All CPR files use TYPE_PLUS
                        rom_type <= TYPE_PLUS;
                    end else begin
                        // Invalid signature
                        header_valid <= 0;
                    end
                    header_state <= 2;
                end
                2: begin
                    // Keep header valid
                    header_valid <= 1;
                end
            endcase
        end else if (is_bin_file) begin
            // For binary files, set basic header info
            header_valid <= 1;
            rom_type <= TYPE_STANDARD;
            rom_size <= ioctl_addr[15:0]; // Use download size as ROM size
        end
    end
    
    // Validation outputs - used for all Plus ROM types
    plus_bios_valid <= header_valid;
    plus_bios_checksum <= rom_checksum;
    plus_bios_version <= rom_version;
end

// Output assignments
assign rom_addr = rom_addr_reg;
assign rom_data = rom_data_reg;
assign rom_wr = active_plus_mode && cart_wr;
assign rom_rd = active_plus_mode && cart_rd;
assign rom_q = rom_data_reg;
assign auto_boot = auto_boot_reg;
assign boot_addr = boot_addr_reg;

endmodule 