/*  plus_controller.v ─ CPC Plus palette, INT timer & GA-mask glue
    --------------------------------------------------------------------------
    2025-06-12  –  final sync-fixed & border-aware edition
*/
module plus_controller #(
    parameter CLK_FREQ_HZ = 32_000_000   // master clock frequency
)(
    // ─── clocks / reset ───────────────────────────────────────────────────
    input  wire        clk,        // 32/48/64 MHz system clock
    input  wire        cen_16,     // 16 MHz pixel-enable (1 tick per GA pixel)
    input  wire        reset_n,

    // ─── Z-80 I/O bus (7Fxx) ──────────────────────────────────────────────
    input  wire [15:0] A,
    input  wire  [7:0] D,
    input  wire        IO_WR,      // level, high while /WR low & /IORQ low

    // ─── CPU memory write bus (for ASIC colour RAM @6400) ────────────────
    input  wire        MEM_WR,     // /WR low during MREQ (same pulse used by MMU)
    input  wire [15:0] MEM_A,      // Z80 address
    input  wire  [7:0] MEM_D,      // data written to memory,

    // ─── Z‑80 interrupt‑acknowledge detector (M1 & /IORQ low) ────────────
    input  wire        cpu_ack,

    // ─── MMU-decoded control lines ────────────────────────────────────────
    input  wire        int_enable, // MRER bit 4
    input  wire        rmr2_active, // level: ASIC window enabled
    input  wire        rmr2_now,   // pulse: RMR2 just written (GA mask)

    // ─── handshake back to Gate-Array ─────────────────────────────────────
    output wire        block_ctrl_en,   // masks GA CTRL reg if 1

    // ─── video timing / pen from Gate-Array ───────────────────────────────
    input  wire        vsync_i,
    input  wire  [3:0] ga_pen,

    // ─── 8-bit RGB output (duplicated nibble ×17) ─────────────────────────
    output wire [7:0]  rgb_r,
    output wire [7:0]  rgb_g,
    output wire [7:0]  rgb_b,

    // ─── stub audio out (silence) ─────────────────────────────────────────
    output wire signed [15:0] dac_l,
    output wire signed [15:0] dac_r,

    // ─── open-drain interrupt to Z-80 ─────────────────────────────────────
    output reg         int_n
);

// -------------------------------------------------------------
// PAL/ASIC I/O write detector  (tests only A15 = 0, ignores A14)
// -------------------------------------------------------------
reg io_wr_q;
always @(posedge clk) io_wr_q <= IO_WR;           // level → edge
wire wr_stb   = IO_WR & ~io_wr_q;                 // 1‑cycle pulse
wire is_7F  = (A[15:8] == 8'h7F);

// palette commands are 00xxxxxx (pointer) or 01xxxxxx (colour RG)
wire pal_stb = wr_stb & is_7F &
               (D[7:6] == 2'b00 || D[7:6] == 2'b01);

// ══════════════════════════════════════════════════════════════════════════
// 1.  GA CTRL mask (for RMR2 writes)
// ══════════════════════════════════════════════════════════════════════════
// Mask GA CTRL register only for a genuine RMR2 write
assign block_ctrl_en = rmr2_now;

// ══════════════════════════════════════════════════════════════════════════
// 2.  PLUS palette   (16 pens  + border)
// ══════════════════════════════════════════════════════════════════════════
// ---------- Plus 4 096-colour palette (0x7F00–0x7F10) --------------------
//   • D7:6 = 00 → pen/border select (D4=1 selects the border ink)
//   • D7:6 = 01 → RED + GREEN byte  (R = D[3:0],  G = A[3:0])
//   • D7:6 = 10 / 11 → **NOT** palette, ignore here
//   Each nibble is written immediately; no waiting for the blue byte.
// -------------------------------------------------------------------------

reg [11:0] palette [0:15]; // 16 inks (border still picked up by GA TTL)
reg  [4:0] pal_ptr;              // 0-15 pens, 16 = border
integer i;

always @(posedge clk) begin
    if (!reset_n) begin
        for (i = 0; i < 16; i = i + 1) palette[i] <= 12'h000;
        pal_ptr <= 5'd0;
    end
    else if (pal_stb) begin
        case (D[7:6])
            //------------------------------------------------------------------
            // 00xxxxxx  –  POINTER (select pen/border)
            //------------------------------------------------------------------
            2'b00:  pal_ptr <= {D[4], D[3:0]};   // bit4 marks border (ink 16)

            //------------------------------------------------------------------
            // 01xxxxxx  –  PALETTE MEMORY WRITE
            //            12‑bit colour is supplied in *two* successive writes:
            //            • First write after pointer gives RED (D3:0) & GREEN (A3:0)
            //            • Second write after pointer gives BLUE (D3:0)
            //------------------------------------------------------------------
            2'b01: begin
                if (pal_ptr < 16) begin
                    palette[pal_ptr][11:8] <= D[3:0];   // RED nibble
                    palette[pal_ptr][ 7:4] <= A[3:0];   // GREEN nibble
                end
            end

            //------------------------------------------------------------------
            // 10x / 11x  –  **NOT** palette; these are MRER, RMR2 or GA MMR.
            //              Ignore them here to avoid polluting the palette.
            //------------------------------------------------------------------
            default: ;  // do nothing
        endcase
    end
    // ---------------------------------------------------------------
    // Memory‑mapped ASIC Colour RAM 0x6400–0x641F (RMR2 bit 5 enabled)
    // Even addr : RED (7:4) & BLUE (3:0)
    // Odd  addr : GREEN (3:0)
    // ---------------------------------------------------------------
    else if (MEM_WR && rmr2_active && (MEM_A[15:5] == 11'h320)) begin
        // 0x6400‑641F => MEM_A[4:1] = colour index 0‑15
        logic [4:0] idx = {1'b0, MEM_A[4:1]}; // force 0‑15 range

        if (!MEM_A[0]) begin               // even = RB nibble byte
            palette[idx][11:8] <= MEM_D[7:4];   // RED
            palette[idx][ 3:0] <= MEM_D[3:0];   // BLUE
        end
        else begin                         // odd  = G nibble byte
            palette[idx][ 7:4] <= MEM_D[3:0];   // GREEN
        end
    end
end

// Warn if a 10xxxxxx or 11xxxxxx ever reaches palette via 7Fxx, but do not abort
always @(posedge clk) if (pal_stb && (D[7] && ~D[6])) begin
    $display("plus_controller WARN: MRER/RMR2 byte %02h seen on 7Fxx (ignored by palette)", D);
end

// -------------------- DEBUG ------------------------------------------------
always @(posedge clk) if (pal_stb) begin
    case (D[7:6])
        2'b00:
            $display("@%0t PEN   sel=%0d border=%b", $time, D[3:0], D[4]);

        2'b01:
            $display("@%0t PAL   ptr=%0d  R=%1h  G=%1h  B=%1h  -> %03h",
                     $time, pal_ptr, D[3:0], A[3:0],
                     palette[pal_ptr][3:0], palette[pal_ptr]);

        default: ; // keep Verilog happy
    endcase

    $write("PALETTE:");
    for (int p = 0; p < 16; p = p + 1) $write("%02h ", palette[p]);
    $display("");

    // Extra trace for memory‑mapped colour RAM
    if (MEM_WR && rmr2_active && (MEM_A[15:5]==11'h320)) begin
        $display("@%0t ASIC-MEM clr idx=%0d %s byte=%02h -> %03h",
                 $time,
                 {1'b0, MEM_A[4:1]},
                 MEM_A[0] ? "G" : "RB",
                 MEM_D,
                 palette[{1'b0, MEM_A[4:1]}]);
    end
end

// -------- one‑pixel latency to align with GA shift register -------------
reg [3:0] pen_lat /* synthesis preserve */;      //   0  cycle
reg [3:0] pen_lat_d1 /* synthesis preserve */;   // +1 cycle
reg [7:0] r8, g8, b8;

always @(posedge clk) if (cen_16) begin
    pen_lat     <= ga_pen;          // capture GA ink ID
    pen_lat_d1  <= pen_lat;         // delay by 1 pixel

    // look‑up and expand (×17) the delayed pen
    {r8,g8,b8}  <= {
        { palette[pen_lat_d1][11:8], palette[pen_lat_d1][11:8] },
        { palette[pen_lat_d1][ 7:4], palette[pen_lat_d1][ 7:4] },
        { palette[pen_lat_d1][ 3:0], palette[pen_lat_d1][ 3:0] }
    };
end

assign rgb_r = r8;
assign rgb_g = g8;
assign rgb_b = b8;

// ══════════════════════════════════════════════════════════════════════════
// 3.  Frame interrupt – 52 µs after VSYNC falling edge
//     • IRQ is level‑held until the CPU executes an INT‑acknowledge cycle
// ══════════════════════════════════════════════════════════════════════════
localparam integer INT_DELAY = CLK_FREQ_HZ / 1_000_000 * 52;  // 52 µs

reg  vsync_d;
reg  irq_latch;                 // 1 while interrupt is pending/active
reg  [$clog2(INT_DELAY+1)-1:0] cnt;

always @(posedge clk) begin
    vsync_d <= vsync_i;

    // Reload 52 µs timer on VSYNC falling edge
    if (vsync_d & ~vsync_i) begin
        cnt       <= INT_DELAY[$clog2(INT_DELAY+1)-1:0];
        irq_latch <= 1'b0;           // clear any previous INT
    end
    else if (cnt != 0) begin         // countdown
        cnt <= cnt - 1'b1;
        if (cnt == 1) irq_latch <= 1'b1;   // assert INT when timer expires
    end

    // Release INT when CPU acknowledges
    if (cpu_ack) irq_latch <= 1'b0;

    // Drive open‑drain INT line (active‑low). If int_enable=0, keep high.
    int_n <= ~(irq_latch & int_enable);
end

// ══════════════════════════════════════════════════════════════════════════
// 4.  DMA sound – stub (silence)
// ══════════════════════════════════════════════════════════════════════════
assign dac_l = 16'sd0;
assign dac_r = 16'sd0;

// ══════════════════════════════════════════════════════════════════════════
// TODO: Sprite engine, scroll, DMA sound FIFOs, etc.
// ══════════════════════════════════════════════════════════════════════════
endmodule