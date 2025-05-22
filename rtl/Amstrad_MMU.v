/*

	Reworked Amstrad MMU for simplicity
	(C) 2018 Sorgelig

--------------------------------------------------------------------------------
--    {@{@{@{@{@{@
--  {@{@{@{@{@{@{@{@  This code is covered by CoreAmstrad synthesis r004
--  {@    {@{@    {@  A core of Amstrad CPC 6128 running on MiST-board platform
--  {@{@{@{@{@{@{@{@
--  {@  {@{@{@{@  {@  CoreAmstrad is implementation of FPGAmstrad on MiST-board
--  {@{@        {@{@   Contact : renaudhelias@gmail.com
--  {@{@{@{@{@{@{@{@   @see http://code.google.com/p/mist-board/
--    {@{@{@{@{@{@     @see FPGAmstrad at CPCWiki
--
--
--------------------------------------------------------------------------------
-- FPGAmstrad_amstrad_motherboard.Amstrad_MMU
-- RAM ROM mapping split
--------------------------------------------------------------------------------
*/

//http://www.grimware.org/doku.php/documentations/devices/gatearray

module Amstrad_MMU
(
	input        CLK,
	input        reset,

	input        ram64k,
	input        romen_n,
	input [255:0]rom_map,
	input        gx4000_mode,    // GX4000 mode compatibility input 
	input        plus_mode,      // Plus mode input
	input        plus_rom_loaded, // Indicates when a Plus ROM has been loaded
	input        asic_enabled,
	input  [7:0] rmr2,

	input        io_WR,

	input  [7:0] D,
	input [15:0] A,
	output reg [22:0] ram_A,
	output reg      asic_reg_sel
);

// Combine inputs for a unified Plus mode
wire active_plus_mode = gx4000_mode | plus_mode;

reg [2:0] RAMmap;
reg [4:0] RAMpage;
reg [7:0] ROMbank;
reg old_wr;

initial begin
	old_wr = 0;
end

always @(posedge CLK) begin
	if (reset) begin
		ROMbank    <= 0;
		RAMmap     <= 0;
		RAMpage    <= 3;
	end
	else begin
		old_wr <= io_WR;
		if (~old_wr & io_WR) begin
			if (~A[15] && D[7:6] == 'b11 && ~ram64k) begin //7Fxx PAL MMR
				RAMpage <= {1'b0, ~A[8], D[5:3]} + 5'd3;
				RAMmap  <= D[2:0];
			end

			// ROM bank selection handling for Plus mode
			if (~A[13]) begin
				ROMbank <= rom_map[D] ? D : 8'h00;
			end
		end
	end
end

always @(posedge CLK) begin
	// Full Plus/GX4000 MMU logic
	// Default: no ASIC register access
	asic_reg_sel = 1'b0;
	
	if (asic_enabled && (A[15:0] >= 16'h4000 && A[15:0] <= 16'h7FFF) && (rmr2[4:3] == 2'b11)) begin
		// Map 0x4000-0x7FFF to ASIC registers
		asic_reg_sel = 1'b1;
		// ram_A is don't care in this case
		ram_A = 23'h0;
	end else if (asic_enabled && (rmr2[4:3] != 2'b11)) begin
		// Cartridge ROM mapping based on rmr2
		// rmr2[2:0] = cart bank, rmr2[4:3] = location
		// 0x00: 0x0000, 0x08: 0x4000, 0x10: 0x8000, 0x18: 0x0000+ASIC
		case ({A[15:13]})
			3'b000: begin // 0x0000-0x1FFF
				if ((rmr2[4:3] == 2'b00) && (A[15:0] < 16'h4000)) begin
					// Cart ROM at 0x0000
					ram_A = {1'b1, (rmr2[2:0]), A[13:0]};
				end else begin
					// Standard RAM/ROM mapping
					ram_A = {2'b00, 5'd2, A[15:14], A[13:0]};
				end
			end
			3'b010: begin // 0x4000-0x5FFF
				if ((rmr2[4:3] == 2'b01) && (A[15:0] >= 16'h4000 && A[15:0] < 16'h6000)) begin
					// Cart ROM at 0x4000
					ram_A = {1'b1, (rmr2[2:0]), A[13:0]};
				end else begin
					ram_A = {2'b00, 5'd2, A[15:14], A[13:0]};
				end
			end
			3'b100: begin // 0x8000-0x9FFF
				if ((rmr2[4:3] == 2'b10) && (A[15:0] >= 16'h8000 && A[15:0] < 16'hA000)) begin
					// Cart ROM at 0x8000
					ram_A = {1'b1, (rmr2[2:0]), A[13:0]};
				end else begin
					ram_A = {2'b00, 5'd2, A[15:14], A[13:0]};
				end
			end
			default: begin
				// Standard RAM/ROM mapping
				ram_A = {2'b00, 5'd2, A[15:14], A[13:0]};
			end
		endcase
	end else begin
		// Standard CPC mapping
		casex({romen_n, RAMmap, A[15:14]})
			'b0_xxx_xx: ram_A[22:14] = {9{A[15]}} & {1'b1, ROMbank};  // lower/upper rom
			'b1_0x1_11,                                               // map1&3 bank3
			'b1_010_xx: ram_A[22:14] = {2'b00, RAMpage,    A[15:14]}; // map2   bank0-3 (ext  0..3)
			'b1_011_01: ram_A[22:14] = {2'b00,    5'd2,       2'b11}; // map3   bank1   (base 3)
			'b1_1xx_01: ram_A[22:14] = {2'b00, RAMpage, RAMmap[1:0]}; // map4-7 bank1   (ext  0..3)
			   default: ram_A[22:14] = {2'b00,    5'd2,    A[15:14]}; // base 64KB map  (base 0..3)
		endcase
		ram_A[13:0] = A[13:0];
	end
end

/*
// Add debug output for memory access
always @(posedge CLK) begin
	if (!romen_n) begin
		$display("[MMU] ROM access: addr=%h mapped_to=%h bank=%h", 
				A, ram_A, ROMbank);
	end
end
*/

endmodule
