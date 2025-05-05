module GX4000
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,
    input         plus_mode,
    
    // CPU interface
    input  [15:0] cpu_addr,
    input   [7:0] cpu_data,
    input         cpu_wr,
    input         cpu_rd,
    
    // Video interface
    input   [1:0] r_in,
    input   [1:0] g_in,
    input   [1:0] b_in,
    input         hblank,
    input         vblank,
    output  [1:0] r_out,
    output  [1:0] g_out,
    output  [1:0] b_out,
    
    // Audio interface
    input   [7:0] cpc_audio_l,
    input   [7:0] cpc_audio_r,
    output  [7:0] audio_l,
    output  [7:0] audio_r,
    
    // Joystick interface
    input   [6:0] joy1,
    input   [6:0] joy2,
    input         joy_swap,
    
    // Cartridge interface
    input         cart_download,
    input  [24:0] cart_addr,
    input   [7:0] cart_data,
    input         cart_wr,
    
    // ROM loading interface
    input         ioctl_wr,
    input  [24:0] ioctl_addr,
    input   [7:0] ioctl_dout,
    input         ioctl_download,
    
    // Status outputs
    output  [7:0] rom_type,
    output [15:0] rom_size,
    output [15:0] rom_checksum,
    output  [7:0] rom_version,
    output [31:0] rom_date,
    output [63:0] rom_title,
    output        asic_valid,
    output  [7:0] asic_status,
    output  [7:0] audio_status,
    
    // Video source selection
    input         use_asic
);

    // Internal signals
    wire [7:0] sprite_pixel;
    wire       sprite_active;
    wire [3:0] sprite_id;
    wire       sprite_collision;
    wire [7:0] sprite_movement;
    wire [7:0] io_dout;
    wire [7:0] collision_reg;
    wire [7:0] config_reg;
    wire [7:0] cpu_data_out;
    wire [22:0] rom_addr;
    wire [7:0] rom_data;
    wire       rom_wr;
    wire       rom_rd;
    wire [7:0] rom_q;
    wire       auto_boot;
    wire [15:0] boot_addr;

    // ROM module instance
    GX4000_rom rom_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_download(ioctl_download),
        .rom_type(rom_type),
        .rom_size(rom_size),
        .rom_checksum(rom_checksum),
        .rom_version(rom_version),
        .rom_date(rom_date),
        .rom_title(rom_title)
    );

    // I/O module instance
    GX4000_io io_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .io_dout(io_dout),
        .joy1(joy1),
        .joy2(joy2),
        .joy_swap(joy_swap)
    );

    // Joystick module instance
    GX4000_joystick joystick_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .joy1(joy1),
        .joy2(joy2),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data_out),
        .cpu_rd(cpu_rd),
        .joy_swap(joy_swap)
    );

    // Memory module instance
    GX4000_memory memory_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .mem_addr(rom_addr),
        .mem_data(rom_data),
        .mem_wr(rom_wr),
        .mem_rd(rom_rd),
        .mem_q(rom_q),
        .cart_download(cart_download),
        .cart_addr(cart_addr),
        .cart_data(cart_data),
        .cart_wr(cart_wr)
    );

    // Video module instance
    GX4000_video video_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .r_in(r_in),
        .g_in(g_in),
        .b_in(b_in),
        .hblank(hblank),
        .vblank(vblank),
        .r_out(video_r_out),
        .g_out(video_g_out),
        .b_out(video_b_out),
        .sprite_pixel(sprite_pixel),
        .sprite_active(sprite_active),
        .sprite_id(sprite_id),
        .collision_reg(collision_reg),
        .config_reg(config_reg)
    );

    // ASIC module instance
    GX4000_ASIC asic_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .r_in(r_in),
        .g_in(g_in),
        .b_in(b_in),
        .hblank(hblank),
        .vblank(vblank),
        .r_out(asic_r_out),
        .g_out(asic_g_out),
        .b_out(asic_b_out),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .cart_download(cart_download),
        .cart_addr(cart_addr),
        .cart_data(cart_data),
        .cart_wr(cart_wr),
        .asic_valid(asic_valid),
        .asic_status(asic_status)
    );

    // Audio module instance
    GX4000_audio audio_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .cpc_audio_l(cpc_audio_l),
        .cpc_audio_r(cpc_audio_r),
        .sprite_id(sprite_id),
        .sprite_collision(sprite_collision),
        .sprite_movement(sprite_movement),
        .hblank(hblank),
        .vblank(vblank),
        .audio_l(audio_l),
        .audio_r(audio_r),
        .audio_status(audio_status)
    );

    // Sprite module instance
    GX4000_sprite sprite_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .hpos(hpos),
        .vpos(vpos),
        .hblank(hblank),
        .vblank(vblank),
        .sprite_pixel(sprite_pixel),
        .sprite_active(sprite_active)
    );

    // Cartridge module instance
    GX4000_cartridge cart_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .cart_addr(cart_addr),
        .cart_data(cart_data),
        .cart_rd(cart_rd),
        .cart_wr(cart_wr),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_download(ioctl_download),
        .rom_addr(rom_addr),
        .rom_data(rom_data),
        .rom_wr(rom_wr),
        .rom_rd(rom_rd),
        .rom_q(rom_q),
        .auto_boot(auto_boot),
        .boot_addr(boot_addr)
    );

    // Video output multiplexing
    wire [1:0] video_r_out, video_g_out, video_b_out;
    wire [1:0] asic_r_out, asic_g_out, asic_b_out;

    assign r_out = use_asic ? asic_r_out : video_r_out;
    assign g_out = use_asic ? asic_g_out : video_g_out;
    assign b_out = use_asic ? asic_b_out : video_b_out;

endmodule 