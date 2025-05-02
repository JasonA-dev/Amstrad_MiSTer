module GX4000_rom
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,
    input         plus_mode,    // New input for Plus mode
    
    // ROM loading interface
    input         ioctl_wr,
    input  [24:0] ioctl_addr,
    input   [7:0] ioctl_dout,
    input         ioctl_download,
    
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
    
    // ROM type definitions
    localparam TYPE_STANDARD = 8'h00;
    localparam TYPE_ENHANCED = 8'h01;
    localparam TYPE_PROTECTED = 8'h02;
    localparam TYPE_PLUS = 8'h01;  // New Plus ROM type
    
    // Error codes
    localparam ERROR_NONE = 8'h00;
    localparam ERROR_INVALID_HEADER = 8'h01;
    localparam ERROR_INVALID_TYPE = 8'h02;
    localparam ERROR_INVALID_SIZE = 8'h03;
    localparam ERROR_CHECKSUM = 8'h04;
    localparam ERROR_PLUS_INVALID = 8'h05;  // New Plus-specific error
    
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
            
            // Plus-specific reset
            plus_bios_valid <= 0;
            plus_bios_checksum <= 0;
            plus_bios_version <= 0;
        end else if (ioctl_download && ioctl_wr) begin
            case (header_state)
                0: begin
                    if (ioctl_addr == 0) begin
                        rom_type <= TYPE_STANDARD;
                        header_state <= 1;
                    end
                end
                1: begin
                    if (ioctl_addr < 32) begin
                        header_data[ioctl_addr] <= ioctl_dout;
                        if (ioctl_addr == 31) begin
                            header_state <= 2;
                        end
                    end
                end
                2: begin
                    // Parse header data
                    rom_type <= header_data[0];
                    rom_size <= {header_data[2], header_data[1]};
                    rom_checksum <= {header_data[4], header_data[3]};
                    rom_version <= header_data[5];
                    rom_date <= {header_data[9], header_data[8], header_data[7], header_data[6]};
                    rom_title <= {
                        header_data[15], header_data[14], header_data[13], header_data[12],
                        header_data[11], header_data[10], header_data[9], header_data[8]
                    };
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