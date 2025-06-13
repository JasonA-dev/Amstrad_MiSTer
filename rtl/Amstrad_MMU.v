// ──────────────────────────────────────────────────────────────────────────────
//  Amstrad_MMU  –  CPC-6128 banking + MRER / RMR2 for CPC Plus
// ──────────────────────────────────────────────────────────────────────────────
//  • Original logic by Sorgelig (2018)
//  • Plus extensions 2025 by JasonA
//
//  New outputs ---------------------------------------------------------------
//    rom_low_on        1 = cartridge visible at 0000-3FFF
//    rom_high_on       1 = cartridge visible at C000-FFFF
//    int_enable        MRER bit4 – frame-INT mask
//    mode0 / mode1     MRER bits2:3 – for GA video mode & PAL DAC
//    rmr2_active       1 = low-bank mapping controlled by RMR2
//    cart_page[2:0]    physical cartridge page selected by RMR2
//    rmr2_now          1-cycle pulse the moment a valid RMR2 byte is written
//
//  Everything else (MMR, DFxx ROMbank, 64-K switch, etc.) is unchanged.
// ──────────────────────────────────────────────────────────────────────────────
module Amstrad_MMU
(
    input         CLK,
    input         reset,

    // Legacy CPC inputs
    input         ram64k,
    input         romen_n,           // GA ROM enable (active-low)
    input  [255:0]rom_map,           // 1 = physical cart page present
    input         io_WR,
    input  [7:0]  D,
    input  [15:0] A,

    // Address out to SDRAM
    output reg [22:0] ram_A,

    // ─── new Plus control outputs ───────────────────────────────────────────
    output        rom_low_on,
    output        rom_high_on,
    output        int_enable,
    output        mode0,
    output        mode1,
    output        rmr2_active,
    output [2:0]  cart_page,
    output        rmr2_now
);
// ──────────────────────────────────────────────────────────────────────────────
//  Internal state
// ──────────────────────────────────────────────────────────────────────────────
reg [2:0] RAMmap;
reg [4:0] RAMpage;
reg [7:0] ROMbank;

reg [7:0] mrer_reg;                 // Plus MRER
reg [7:0] rmr2_reg;                 // Plus RMR2
reg       rmr2_pulse;               // 1-clk strobe

// Edge detector for IO_WR
reg old_wr;
always @(posedge CLK) old_wr <= io_WR;

always @(posedge CLK) if (!reset && !rmr2_active) begin
    if ((A[15:14] == 2'b00) && page_sel[8]) begin
        $display("%t **MMU ASSERT** : Cart overlay seen in RAM map A=%h page_sel=%h", $time, A, page_sel);
        $stop;
    end
end

// ──────────────────────────────────────────────────────────────────────────────
//  I/O-port decode (writes to 7Fxx / DFxx)
// ──────────────────────────────────────────────────────────────────────────────
always @(posedge CLK) begin
    if (reset) begin
        ROMbank    <= 8'd0;
        RAMmap     <= 3'd0;
        RAMpage    <= 5'd3;
        mrer_reg   <= 8'h88;
        rmr2_reg   <= 8'h00;
        rmr2_pulse <= 1'b0;
    end
    else begin
        rmr2_pulse <= 1'b0;               // auto-clear

        if (~old_wr & io_WR) begin        // rising edge of /WR
            // -------- 7Fxx group -------------------------------------------
            if (A[15:8] == 8'h7F) begin
                // Classic Gate-Array MMR (xxxx xx11)
                if (D[7:6] == 2'b11 && ~ram64k) begin
                    RAMpage <= {1'b0, ~A[8], D[5:3]} + 5'd3;
                    RAMmap  <= D[2:0];
                end
                // Plus MRER (D7-5 = 100)
                else if (D[7:5] == 3'b100) begin
                    mrer_reg <= D;
                end
                // Plus RMR2 (D7-5 = 101)
                else if (D[7:5] == 3'b101) begin
                    rmr2_reg   <= D;
                    rmr2_pulse <= 1'b1;   // tell the GA to ignore this ctrl byte
                end
            end

            // -------- DFxx group (upper-bank ROM select) --------------------
            if (A[15:8]==8'hDF) ROMbank <= D;   // no rom_map test
        end
    end
end

assign rmr2_now     = rmr2_pulse;

// ──────────────────────────────────────────────────────────────────────────────
//  Decode MRER bits for external use
// ──────────────────────────────────────────────────────────────────────────────
wire upper_disable = mrer_reg[6];
assign rom_high_on = ~upper_disable & ~mrer_reg[1];
assign rom_low_on  = ~upper_disable & ~mrer_reg[0];

assign mode0        =  mrer_reg[2];
assign mode1        =  mrer_reg[3];
assign int_enable   =  mrer_reg[4];

assign rmr2_active = rmr2_reg[5] & ~mrer_reg[3];
assign cart_page    =  rmr2_reg[2:0];

// ──────────────────────────────────────────────────────────────────────────────
//  Physical page selection (9 MSBs)
// ──────────────────────────────────────────────────────────────────────────────
reg [8:0] page_sel;

always @* begin
    // ---------- Default 6128 map (identical to original MMU) ---------------
    casex ({romen_n, RAMmap, A[15:14]})
        7'b0_xxx_xx: page_sel = {9{A[15]}} & {1'b1, ROMbank};            // ROM overlay
        7'b1_0x1_11,
        7'b1_010_xx: page_sel = {2'b00, RAMpage,    A[15:14]};
        7'b1_011_01: page_sel = {2'b00,       5'd2, 2'b11};
        7'b1_1xx_01: page_sel = {2'b00, RAMpage, RAMmap[1:0]};
        default     : page_sel = {2'b00,       5'd2, A[15:14]};
    endcase

    // ---------- Plus low-bank override (RMR2) ------------------------------
    if (rmr2_active && rom_low_on) begin
        case (rmr2_reg[4:3])
            2'b00: if (A[15:14]==2'b00) page_sel = {1'b1, A[15:14], cart_page, 3'b000};
            2'b01: if (A[15:14]==2'b01) page_sel = {1'b1, A[15:14], cart_page, 3'b000};
            2'b10: if (A[15:14]==2'b10) page_sel = {1'b1, A[15:14], cart_page, 3'b000};
            2'b11: if (A[15:14]==2'b11) page_sel = {1'b1, A[15:14], cart_page, 3'b000};
        endcase
    end
end

// ──────────────────────────────────────────────────────────────────────────────
//  Final SDRAM address:  page_sel[8:0] ◦ CPU A[13:0]
// ──────────────────────────────────────────────────────────────────────────────
always @* begin
    ram_A = {page_sel, A[13:0]};
end

endmodule