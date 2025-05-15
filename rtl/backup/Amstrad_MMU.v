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

	input        io_WR,

	input  [7:0] D,
	input [15:0] A,
	output reg [22:0] ram_A
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
				if (active_plus_mode && D == 8'h07) begin
					// Special case: When in Plus mode and selecting ROM 7,
					// use Plus ROM area
					ROMbank <= 8'h07;
				end
				else begin
					// Normal ROM selection for other cases
					ROMbank <= rom_map[D] ? D : 8'h00;
				end
			end
		end
	end
end

always @(*) begin
	if (active_plus_mode) begin
		// Unified Plus mode mapping
		casex({romen_n, A[15:14]})
			// When ROM is enabled
			'b0_00: begin
				// Lower ROM - always use standard OS ROM for keyboard access
				ram_A[22:14] = {1'b1, 8'h00};
			end
			'b0_11: begin
				// Upper ROM with ROM banking
				if (ROMbank == 8'h00)
					ram_A[22:14] = {1'b1, 8'h07};      // Default bank 7 (BASIC)
				else if (ROMbank == 8'h07 && plus_rom_loaded)
					ram_A[22:14] = {1'b1, 8'h01};      // Plus ROM bank
				else
					ram_A[22:14] = {1'b1, ROMbank};    // Other ROM banks (standard mapping)
			end
			
			// Standard RAM mapping for compatibility
			default: begin
				ram_A[22:14] = {2'b00, 5'd2, A[15:14]}; // Standard 64KB mapping
			end
		endcase
	end
	else begin
		// Standard CPC mapping
		casex({romen_n, RAMmap, A[15:14]})
			'b0_xxx_xx: ram_A[22:14] = {9{A[15]}} & {1'b1, ROMbank};  // lower/upper rom
			'b1_0x1_11,                                               // map1&3 bank3
			'b1_010_xx: ram_A[22:14] = {2'b00, RAMpage,    A[15:14]}; // map2   bank0-3 (ext  0..3)
			'b1_011_01: ram_A[22:14] = {2'b00,    5'd2,       2'b11}; // map3   bank1   (base 3)
			'b1_1xx_01: ram_A[22:14] = {2'b00, RAMpage, RAMmap[1:0]}; // map4-7 bank1   (ext  0..3)
			   default: ram_A[22:14] = {2'b00,    5'd2,    A[15:14]}; // base 64KB map  (base 0..3)
		endcase
	end

	ram_A[13:0] = A[13:0];
end

endmodule
