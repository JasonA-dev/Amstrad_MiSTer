module GX4000_rom
(
    input         clk_sys,
    input         reset,
    
    // File loading interface
    input         file_wr,
    input  [24:0] file_addr,
    input   [7:0] file_data,
    input         file_load,
    
    // ROM format information
    output reg [7:0] rom_type,
    output reg [15:0] rom_size,
    output reg [15:0] rom_checksum,
    output reg [7:0] rom_version,
    output reg [31:0] rom_date,
    output reg [63:0] rom_title,
    
    // Plus-specific outputs
    output reg plus_bios_valid,
    output reg [15:0] plus_bios_checksum,
    output reg [7:0] plus_bios_version
);

    // ROM header registers
    reg [7:0] header_state = 0;
    reg header_valid = 0;
    reg [7:0] header_data[0:31];
    reg [31:0] riff_signature;
    reg [31:0] ams_signature;
    
    // ROM type definitions
    localparam TYPE_STANDARD = 8'h00;
    
    // ROM loading state machine
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
            
            // Plus-specific reset
            plus_bios_valid <= 0;
            plus_bios_checksum <= 0;
            plus_bios_version <= 0;
        end else if (file_load && file_wr) begin
            case (header_state)
                0: begin
                    // Store header data
                    header_data[file_addr[4:0]] <= file_data;
                    
                    // Build RIFF signature (first 4 bytes)
                    if (file_addr < 4) begin
                        case (file_addr)
                            0: riff_signature[31:24] <= file_data;
                            1: riff_signature[23:16] <= file_data;
                            2: riff_signature[15:8] <= file_data;
                            3: riff_signature[7:0] <= file_data;
                        endcase
                    end
                    // Build AMS! signature (bytes 8-11)
                    else if (file_addr >= 8 && file_addr < 12) begin
                        case (file_addr)
                            8: ams_signature[31:24] <= file_data;
                            9: ams_signature[23:16] <= file_data;
                            10: ams_signature[15:8] <= file_data;
                            11: ams_signature[7:0] <= file_data;
                        endcase
                    end
                    
                    // Move to parsing state when header is complete
                    if (file_addr == 31) begin
                        header_state <= 1;
                        $display("Header data loaded");
                        $display("RIFF signature: %h", riff_signature);
                        $display("AMS! signature: %h", ams_signature);
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
                        $display("Valid ROM header found!");
                        $display("  Type: %h", rom_type);
                        $display("  Size: %h", rom_size);
                        $display("  Checksum: %h", rom_checksum);
                        $display("  Version: %h", rom_version);
                        $display("  Date: %h", rom_date);
                        $display("  Title: %h", rom_title);
                    end else begin
                        // Invalid signature
                        header_valid <= 0;
                        $display("Invalid ROM header!");
                        $display("Expected RIFF: %h", 32'h52494646);
                        $display("Expected AMS!: %h", 32'h414D5321);
                    end
                    header_state <= 2;
                end
                2: begin
                    // Keep header valid
                    header_valid <= 1;
                end
            endcase
        end
        
        // Plus-specific outputs
        plus_bios_valid <= header_valid;
        plus_bios_checksum <= rom_checksum;
        plus_bios_version <= rom_version;
    end
    
endmodule 
