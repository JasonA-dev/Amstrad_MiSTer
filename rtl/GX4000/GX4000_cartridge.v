module GX4000_cartridge
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,
    input         plus_mode,
    
    // Cartridge interface
    input  [15:0] cart_addr,
    input   [7:0] cart_data,
    input         cart_rd,
    input         cart_wr,
    
    // ROM loading interface
    input         ioctl_wr,
    input  [24:0] ioctl_addr,
    input   [7:0] ioctl_dout,
    input         ioctl_download,
    
    // Memory interface
    output [22:0] rom_addr,
    output  [7:0] rom_data,
    output        rom_wr,
    output        rom_rd,
    output  [7:0] rom_q,
    
    // Auto-boot interface
    output        auto_boot,
    output [15:0] boot_addr
);

// Internal registers
reg [7:0] rom_bank;
reg [7:0] rom_data_reg;
reg [22:0] rom_addr_reg;
reg auto_boot_reg;
reg [15:0] boot_addr_reg;

// ROM bank selection
always @(posedge clk_sys) begin
    if (reset) begin
        rom_bank <= 8'h00;
        auto_boot_reg <= 0;
        boot_addr_reg <= 16'h0000;
    end else if (gx4000_mode && cart_wr && cart_addr[15:8] == 8'h70) begin
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
    if (gx4000_mode && cart_rd) begin
        rom_addr_reg <= {rom_bank, cart_addr[14:0]};
        rom_data_reg <= cart_data;
    end
end

// Output assignments
assign rom_addr = rom_addr_reg;
assign rom_data = rom_data_reg;
assign rom_wr = gx4000_mode && cart_wr;
assign rom_rd = gx4000_mode && cart_rd;
assign rom_q = rom_data_reg;
assign auto_boot = auto_boot_reg;
assign boot_addr = boot_addr_reg;

endmodule 