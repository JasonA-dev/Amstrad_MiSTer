`timescale 1ps / 1ps
//
// TV80 8-Bit Microprocessor Core
// Based on the VHDL T80 core by Daniel Wallner (jesus@opencores.org)
//
// Copyright (c) 2004 Guy Hutch...
// 
// Permission is hereby granted, free of charge, to any person obtaining a 
// copy of this software and associated documentation files (the "Software"), 
// to deal in the Software without restriction, including without limitation 
// the rights to use, copy, modify, merge, publish, distribute, sublicense, 
// and/or sell copies of the Software, and to permit persons to whom the 
// Software is furnished to do so, subject to the following conditions:
//  ...
//

module tv80s
#(
    parameter Mode    = 0,  // 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
    parameter T2Write = 1,  // 0 => wr_n active in T3, !=0 => wr_n active in T2
    parameter IOWait  = 1   // 0 => Single cycle I/O, 1 => Std I/O cycle
)
(
    input         reset_n, 
    input         clk, 
    input         cen,      // <--- added clock enable
    input         wait_n, 
    input         int_n, 
    input         nmi_n, 
    input         busrq_n, 
    output        busak_n, 
    output        m1_n, 
    output        mreq_n, 
    output        iorq_n, 
    output        rd_n, 
    output        wr_n, 
    output        rfsh_n, 
    output        halt_n, 
    output [15:0] A, 
    input  [7:0]  di,
    output [7:0]  dout
);

  reg           mreq_n_reg; 
  reg           iorq_n_reg; 
  reg           rd_n_reg; 
  reg           wr_n_reg;
  reg  [7:0]    di_reg;

  wire          intcycle_n;
  wire          no_read;
  wire          write;
  wire          iorq;
  wire [6:0]    mcycle;
  wire [6:0]    tstate;

  assign mreq_n = mreq_n_reg;
  assign iorq_n = iorq_n_reg;
  assign rd_n   = rd_n_reg;
  assign wr_n   = wr_n_reg;

  // tv80_core instantiation
  tv80_core #(Mode, IOWait) i_tv80_core
  (
    .cen         (cen),
    .m1_n        (m1_n),
    .iorq        (iorq),
    .no_read     (no_read),
    .write       (write),
    .rfsh_n      (rfsh_n),
    .halt_n      (halt_n),
    .wait_n      (wait_n),
    .int_n       (int_n),
    .nmi_n       (nmi_n),
    .reset_n     (reset_n),
    .busrq_n     (busrq_n),
    .busak_n     (busak_n),
    .clk         (clk),
    .IntE        (),
    .stop        (),
    .A           (A),
    .dinst       (di),     // directly from 'di' for instruction fetch
    .di          (di_reg), // latched data for data reads
    .dout        (dout),
    .mc          (mcycle),
    .ts          (tstate),
    .intcycle_n  (intcycle_n)
  );

  always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      rd_n_reg   <= 1'b1;
      wr_n_reg   <= 1'b1;
      iorq_n_reg <= 1'b1;
      mreq_n_reg <= 1'b1;
      di_reg     <= 8'b0;
    end
    else if (cen) begin
      // default to inactive each cycle
      rd_n_reg   <= 1'b1;
      wr_n_reg   <= 1'b1;
      iorq_n_reg <= 1'b1;
      mreq_n_reg <= 1'b1;

      if (mcycle[0]) begin
        // M1 cycle (opcode fetch / interrupt ack)
        if (tstate[1] || (tstate[2] && (wait_n == 1'b0))) begin
          rd_n_reg   <= ~intcycle_n;
          mreq_n_reg <= ~intcycle_n;
          iorq_n_reg <= intcycle_n;
        end
        // Refresh could be here if included
      end else begin
        // memory read
        if ((tstate[1] || (tstate[2] && (wait_n == 1'b0))) && (no_read == 1'b0) && (write == 1'b0)) begin
          rd_n_reg   <= 1'b0;
          iorq_n_reg <= ~iorq;
          mreq_n_reg <= iorq;
        end
        // memory/IO write
        if (T2Write == 0) begin
          // wr_n active in T3
          if (tstate[2] && write) begin
            wr_n_reg   <= 1'b0;
            iorq_n_reg <= ~iorq;
            mreq_n_reg <= iorq;
          end
        end else begin
          // wr_n active in T2
          if ((tstate[1] || (tstate[2] && (wait_n == 1'b0))) && write) begin
            wr_n_reg   <= 1'b0;
            iorq_n_reg <= ~iorq;
            mreq_n_reg <= iorq;
          end
        end
      end

      // latch data in T3 if reading
      if (tstate[2] && wait_n)
        di_reg <= di;
    end
  end

endmodule