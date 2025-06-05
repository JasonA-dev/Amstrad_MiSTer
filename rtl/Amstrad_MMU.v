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
	input        io_WR,

	input        plus_mode,

	input  [7:0] D,
	input [15:0] A,
	output reg [22:0] ram_A
);

reg [2:0] RAMmap;
reg [4:0] RAMpage;
reg [7:0] ROMbank;
reg old_wr = 0;

// Internal registers
reg [7:0] ram_config_reg;
reg [7:0] mrer_reg;
reg [7:0] rom_select_reg;
reg [7:0] rmr2_reg;

always @(posedge CLK) begin
	if (reset) begin
		ROMbank    <= 0;
		RAMmap     <= 0;
		RAMpage    <= 3;
		ram_config_reg <= 0;
		mrer_reg <= 0;
		rom_select_reg <= 0;
		rmr2_reg <= 0;
	end
	else begin
		old_wr <= io_WR;
		if (~old_wr & io_WR) begin
			// Decode 7Fxxh registers
			if (A[15:8] == 8'h7F) begin
				if (D[7:6] == 2'b11 && ~ram64k) begin
					// Memory mapping register (RAM)
					RAMpage <= {1'b0, ~A[8], D[5:3]} + 5'd3;
					RAMmap  <= D[2:0];
					ram_config_reg <= D;
				end
				else if (D[7:5] == 3'b101 && plus_mode) begin
					// RMR2 (Secondary ROM mapping register)
					rmr2_reg <= D;
				end
				else if (D[7:5] == 3'b100 && plus_mode) begin
					// MRER (Mode and ROM enable register)
					mrer_reg <= D;
				end
			end

			// Decode DFxxh (ROM Select Register)
			if (A[15:8] == 8'hDF) begin
				rom_select_reg <= D;
				if (plus_mode) begin
					if (rmr2_reg[5]) begin
						ROMbank <= (rmr2_reg[2:0]);
					end else begin
						ROMbank <= rom_map[D] ? D : 8'h00;
					end
				end else begin
					ROMbank <= rom_map[D] ? D : 8'h00;
				end
			end
		end
	end
end

always @(*) begin
	if (plus_mode && rmr2_reg[5]) begin
		// Plus mode with ASIC registers enabled
		// RMR2[4:3] selects bank position, RMR2[2:0] selects bank number
		case (rmr2_reg[4:3])
			2'b00: begin // Located at 0x0000
				if (A[15:14] == 2'b00) begin
					ram_A[22:14] = {1'b0, rmr2_reg[2:0], 1'b0};  // Bank 0
				end else if (A[15:14] == 2'b01) begin
					ram_A[22:14] = {1'b0, rmr2_reg[2:0], 1'b1};  // Bank 1
				end else begin
					ram_A[22:14] = {2'b00, RAMpage, A[15:14]};
				end
			end
			2'b01: begin // Located at 0x4000
				if (A[15:14] == 2'b10) begin
					ram_A[22:14] = {1'b0, rmr2_reg[2:0], 1'b0};  // Bank 2
				end else if (A[15:14] == 2'b11) begin
					ram_A[22:14] = {1'b0, rmr2_reg[2:0], 1'b1};  // Bank 3
				end else begin
					ram_A[22:14] = {2'b00, RAMpage, A[15:14]};
				end
			end
			2'b10: begin // Located at 0x8000
				if (A[15:14] == 2'b00) begin
					ram_A[22:14] = {1'b0, rmr2_reg[2:0], 1'b0};  // Bank 4
				end else if (A[15:14] == 2'b01) begin
					ram_A[22:14] = {1'b0, rmr2_reg[2:0], 1'b1};  // Bank 5
				end else begin
					ram_A[22:14] = {2'b00, RAMpage, A[15:14]};
				end
			end
			2'b11: begin // Located at 0x0000, ASIC registers enabled
				if (A[15:14] == 2'b00) begin
					ram_A[22:14] = {1'b0, rmr2_reg[2:0], 1'b0};  // Bank 0
				end else if (A[15:14] == 2'b01) begin
					ram_A[22:14] = {1'b0, rmr2_reg[2:0], 1'b1};  // Bank 1
				end else begin
					ram_A[22:14] = {2'b00, RAMpage, A[15:14]};
				end
			end
		endcase
	end else if (plus_mode && mrer_reg[5]) begin
		// Plus mode with MRER enabled
		// Use MRER for video mode and ROM enable
		casex({romen_n, mrer_reg[1:0], A[15:14]})
			'b0_xx_xx: ram_A[22:14] = {9{A[15]}} & {1'b1, ROMbank};
			'b1_0x_11,
			'b1_10_xx: ram_A[22:14] = {2'b00, RAMpage, A[15:14]};
			'b1_11_01: ram_A[22:14] = {2'b00, 5'd2, 2'b11};
			'b1_1x_01: ram_A[22:14] = {2'b00, RAMpage, mrer_reg[1:0]};
			default: ram_A[22:14] = {2'b00, 5'd2, A[15:14]};
		endcase
	end else begin
		// Standard mode
		casex({romen_n, RAMmap, A[15:14]})
			'b0_xxx_xx: ram_A[22:14] = {9{A[15]}} & {1'b1, ROMbank};
			'b1_0x1_11,
			'b1_010_xx: ram_A[22:14] = {2'b00, RAMpage, A[15:14]};
			'b1_011_01: ram_A[22:14] = {2'b00, 5'd2, 2'b11};
			'b1_1xx_01: ram_A[22:14] = {2'b00, RAMpage, RAMmap[1:0]};
			default: ram_A[22:14] = {2'b00, 5'd2, A[15:14]};
		endcase
	end
	ram_A[13:0] = A[13:0];
end

endmodule