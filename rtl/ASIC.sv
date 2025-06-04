module ASIC
(
    input         clk_sys,
    input         reset,
    input         plus_mode,      // Plus mode enable
    
    // CPU interface
    input  [15:0] cpu_addr,      // CPU address bus
    input   [7:0] cpu_data_in,   // CPU data input
    input         cpu_wr,        // CPU write strobe
    input         cpu_rd,        // CPU read strobe
    output [7:0]  cpu_data_out,  // CPU data output
    output        cpu_data_out_en,  // CPU data output enable
    output [7:0]  asic_data_out,  // ASIC data output
    output        asic_data_out_en,  // ASIC data output enable
    
    // Video outputs
    output [7:0]  ppi_port_a,
    output [7:0]  ppi_port_b,
    output [7:0]  ppi_port_c,
    output [7:0]  crtc_regs[0:31],
    output [7:0]  crtc_reg_select,
    output        acid_unlocked,
    
    // Configuration outputs
    output [7:0]  ram_config,
    output [7:0]  rom_config,
    output [7:0]  rom_select,
    output [4:0]  current_pen,
    output [7:0]  pen_registers,
    output [7:0]  mrer,
    output [7:0]  rmr2,

    // Breakpoint control
    output [31:0] break_point,  // Breakpoint address
    input  [31:0] current_pc    // Current program counter
);

    // Instantiate ASIC registers
    ASIC_registers asic_regs
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data_in(cpu_data_in),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .cpu_data_out(cpu_data_out),
        .cpu_data_out_en(cpu_data_out_en),
        .asic_data_out(asic_data_out),
        .asic_data_out_en(asic_data_out_en),
        
        // Video outputs
        .ppi_port_a(ppi_port_a),
        .ppi_port_b(ppi_port_b),
        .ppi_port_c(ppi_port_c),
        .crtc_regs_reg(crtc_regs),
        .crtc_reg_select(crtc_reg_select),
        .acid_unlocked(acid_unlocked),
        
        // Configuration outputs
        .ram_config(ram_config),
        .rom_config(rom_config),
        .rom_select(rom_select),
        .current_pen(current_pen),
        .pen_registers(pen_registers),
        .mrer(mrer),
        .rmr2(rmr2)
    );

endmodule
