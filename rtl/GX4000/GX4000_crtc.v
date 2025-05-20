module GX4000_crtc
(
    input         clk_sys,
    input         reset,
    input         plus_mode,
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data,
    input         cpu_wr,
    input         cpu_rd,
    output  [7:0] cpu_dout,
    
    // Video interface
    output  [3:0] r_out,
    output  [3:0] g_out,
    output  [3:0] b_out,
    
    // ASIC RAM interface
    output [13:0] asic_ram_addr,
    output        asic_ram_rd,
    input  [7:0]  asic_ram_q,
    output        asic_ram_wr,
    output [7:0]  asic_ram_din,
    
    // Interrupt output
    output        pri_irq,

    // CRTC interface from motherboard
    input         crtc_clken,
    input         crtc_nclken,
    input  [13:0] crtc_ma,
    input   [4:0] crtc_ra,
    input         crtc_de,
    input         crtc_field,
    input         crtc_cursor,
    input         crtc_vsync,
    input         crtc_hsync,
    
    // Motherboard RGB inputs
    input   [1:0] mb_r,
    input   [1:0] mb_g,
    input   [1:0] mb_b,
    
    // CRTC register write interface to motherboard
    output        crtc_enable,
    output        crtc_cs_n,
    output        crtc_r_nw,
    output        crtc_rs,
    output  [7:0] crtc_data,

    // Sprite interface
    output        sprite_active_out,
    output [3:0]  sprite_id_out,
    output [7:0]  collision_reg
);

    // Video system signals
    wire [7:0]  video_collision_reg;
    wire        video_sprite_active;
    wire [3:0]  video_sprite_id;
    
    // Video system instance
    GX4000_video video_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .plus_mode(plus_mode),
        
        // CRTC Interface
        .crtc_clken(crtc_clken),
        .crtc_nclken(crtc_nclken),
        .crtc_ma(crtc_ma),
        .crtc_ra(crtc_ra),
        .crtc_de(crtc_de),
        .crtc_field(crtc_field),
        .crtc_cursor(crtc_cursor),
        .crtc_vsync(crtc_vsync),
        .crtc_hsync(crtc_hsync),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        
        // Video input (from motherboard RGB in non-Plus mode, from ASIC RAM in Plus mode)
        .r_in(mb_r),
        .g_in(mb_g),
        .b_in(mb_b),
        
        // Video interface
        .hpos(crtc_ma[9:0]),
        .vpos(crtc_ra),
        .hblank(~crtc_de),
        .vblank(~crtc_vsync),
        
        // Video output
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        
        // Sprite interface
        .sprite_active_out(video_sprite_active),
        .sprite_id_out(video_sprite_id),
        .collision_reg(video_collision_reg),
        
        // ASIC RAM interface
        .asic_ram_addr(asic_ram_addr),
        .asic_ram_rd(asic_ram_rd),
        .asic_ram_q(asic_ram_q),
        .asic_ram_wr(asic_ram_wr),
        .asic_ram_din(asic_ram_din),
        
        // Interrupt output
        .pri_irq(pri_irq)
    );

    // Synchronize sprite signals
    reg sprite_active_sync;
    reg [3:0] sprite_id_sync;
    reg [7:0] collision_reg_sync;

    always @(posedge clk_sys) begin
        if (reset) begin
            sprite_active_sync <= 1'b0;
            sprite_id_sync <= 4'h0;
            collision_reg_sync <= 8'h00;
        end else begin
            sprite_active_sync <= video_sprite_active;
            sprite_id_sync <= video_sprite_id;
            collision_reg_sync <= video_collision_reg;
        end
    end

    // Connect synchronized outputs
    assign sprite_active_out = sprite_active_sync;
    assign sprite_id_out = sprite_id_sync;
    assign collision_reg = collision_reg_sync;

    // CRTC register write control
    assign crtc_enable = (cpu_addr[15:8] == 8'hBC) && (cpu_wr || cpu_rd);
    assign crtc_cs_n = ~(cpu_addr[15:8] == 8'hBC);
    assign crtc_r_nw = ~cpu_wr;
    assign crtc_rs = cpu_addr[8];
    assign crtc_data = cpu_data;

    // Pass through CPU data for CRTC register access
    assign cpu_dout = (cpu_addr[15:8] == 8'hBC) ? 8'h00 : 8'hFF;

endmodule 