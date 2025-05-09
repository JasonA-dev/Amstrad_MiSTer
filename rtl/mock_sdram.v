// mock_sdram.v - Simplified SDRAM module for verilator simulation
// This module provides basic memory functionality without the actual SDRAM interface

module mock_sdram (
	// SDRAM interface stubs (unused in simulation)
	inout  [15:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output [12:0] SDRAM_A,    // 13 bit multiplexed address bus
	output        SDRAM_DQML, // byte mask
	output        SDRAM_DQMH, // byte mask
	output  [1:0] SDRAM_BA,   // two banks
	output        SDRAM_nCS,  // a single chip select
	output        SDRAM_nWE,  // write enable
	output        SDRAM_nRAS, // row address select
	output        SDRAM_nCAS, // columns address select
	output        SDRAM_CLK,
	output        SDRAM_CKE,

	// cpu/chipset interface
	input         init,       // init signal after FPGA config to initialize RAM
	input         clk,        // sdram is accessed at up to 128MHz
	input         clkref,     // reference clock to sync to
	
	input   [1:0] bank,
	input   [7:0] din,        // data input from chipset/cpu
	output  [7:0] dout,       // data output to chipset/cpu
	input  [22:0] addr,       // 23 bit byte address
	input         oe,         // cpu/chipset requests read
	input         we,         // cpu/chipset requests write

	output [15:0] vram_dout,
	input  [22:0] vram_addr,

	input  [22:0] tape_addr,
	input   [7:0] tape_din,
	output  [7:0] tape_dout,

	input         tape_wr,
	output        tape_wr_ack,

	input         tape_rd,
	output reg    tape_rd_ack
);

// Drive unused outputs to reasonable values
assign SDRAM_A = 13'h0;
assign SDRAM_BA = 2'b00;
assign SDRAM_nWE = 1'b1;
assign SDRAM_nRAS = 1'b1;
assign SDRAM_nCAS = 1'b1;
assign SDRAM_nCS = 1'b1;
assign SDRAM_CLK = 1'b0;
assign SDRAM_CKE = 1'b1;
assign SDRAM_DQML = 1'b0;
assign SDRAM_DQMH = 1'b0;
assign SDRAM_DQ = 16'hZZZZ;

// Memory implementation using arrays
reg [7:0] ram[0:8388607]; // 8MB of RAM (23-bit address space)
reg [7:0] out_data;

// Debug signals for ROM loading analysis
wire [22:0] debug_addr = addr;
wire [3:0] addr_lsb = addr[3:0];
wire addr_bit3 = addr[3];

// Simple memory read/write logic
assign dout = oe ? out_data : 8'hFF;

// Video RAM data
reg [15:0] vram_data;
assign vram_dout = vram_data;

// Tape interface
reg [7:0] tape_data;
assign tape_dout = tape_data;
assign tape_wr_ack = tape_wr; // Immediate acknowledgment in simulation

// Memory access logic
always @(posedge clk) begin
    // CPU/chipset read/write
    if (we) begin
        // Always write to the original address
        ram[addr] <= din;
    end
    
    if (oe) begin
        out_data <= ram[addr];
    end
    
    // Video memory read
    vram_data <= {ram[vram_addr+1], ram[vram_addr]};
    
    // Tape interface
    if (tape_wr) begin
        ram[tape_addr] <= tape_din;
    end
    
    if (tape_rd) begin
        tape_data <= ram[tape_addr];
        tape_rd_ack <= ~tape_rd_ack; // Toggle ack to indicate completion
    end
end

// Initialize memory to zeros
initial begin
    integer i;
    for (i = 0; i < 8388607; i = i + 1) begin
        ram[i] = 8'h00;
    end
    
    out_data = 8'h00;
    vram_data = 16'h0000;
    tape_data = 8'h00;
    tape_rd_ack = 0;
end

endmodule 