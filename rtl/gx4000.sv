module GX4000
(
    input         clk_sys,
    input         reset,
    input         gx4000_mode,    // GX4000 mode compatibility input
    input         plus_mode,      // Plus mode input
    input         use_asic,       // Control whether to use the ASIC for video processing
    
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
    input   [7:0] ioctl_index,   // Added index to distinguish between file types
    
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
    
    // Plus-specific outputs
    output        plus_bios_valid
);

    // Combine both inputs for a unified Plus mode 
    wire active_plus_mode = gx4000_mode | plus_mode;

    // Internal signals
    wire [7:0] io_dout;
    wire [22:0] rom_addr;
    wire [7:0] rom_data;
    wire       rom_wr;
    wire       rom_rd;
    wire [7:0] rom_q;
    wire       auto_boot;
    wire [15:0] boot_addr;
    wire [15:0] plus_bios_checksum;
    wire [7:0]  plus_bios_version;
    
    // Cartridge control signals
    wire       cart_rd = 1'b0;  // Fixed implicit net - set to 0 as it's only an input to cart_inst
    
    // Sprite-related signals from video module
    wire [3:0] sprite_id;
    wire       sprite_active;
    wire [7:0] collision_reg;
    
    // I/O module instance
    GX4000_io io_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(active_plus_mode),
        .plus_mode(active_plus_mode),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .io_dout(io_dout),
        .joy1(joy1),
        .joy2(joy2),
        .joy_swap(joy_swap)
    );

    // Video module instance (with integrated sprite handling)
    GX4000_video video_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(active_plus_mode & use_asic),
        .plus_mode(active_plus_mode & use_asic),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        
        // Video input
        .r_in(r_in),
        .g_in(g_in),
        .b_in(b_in),
        .hblank(hblank),
        .vblank(vblank),
        
        // Video output
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        
        // Sprite interface outputs (for audio module)
        .sprite_active(sprite_active),
        .sprite_id(sprite_id),
        .collision_reg(collision_reg)
    );

    // Advanced Cartridge Interface Device (ACID) module instance
    GX4000_ACID acid_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(active_plus_mode & use_asic),
        .plus_mode(active_plus_mode & use_asic),
        .cpu_addr(cpu_addr),
        .cpu_data_in(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .cpu_data_out(),
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
        .gx4000_mode(active_plus_mode & use_asic),
        .plus_mode(active_plus_mode & use_asic),
        .cpu_addr(cpu_addr),
        .cpu_data(cpu_data),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .cpc_audio_l(cpc_audio_l),
        .cpc_audio_r(cpc_audio_r),
        .sprite_id(sprite_id),                 // Connect to sprite signals from video module
        .sprite_collision(sprite_active),      // Use sprite_active as collision signal
        .sprite_movement(collision_reg),       // Use collision register
        .hblank(hblank),
        .vblank(vblank),
        .audio_l(audio_l),
        .audio_r(audio_r),
        .audio_status(audio_status)
    );

    // Consolidated cartridge module instance
    GX4000_cartridge cart_inst
    (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(active_plus_mode),
        .plus_mode(active_plus_mode),
        .cart_addr(cart_addr),
        .cart_data(cart_data),
        .cart_rd(cart_rd),
        .cart_wr(cart_wr),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr),
        .ioctl_dout(ioctl_dout),
        .ioctl_download(ioctl_download),
        .ioctl_index(ioctl_index),
        .rom_addr(rom_addr),
        .rom_data(rom_data),
        .rom_wr(rom_wr),
        .rom_rd(rom_rd),
        .rom_q(rom_q),
        .auto_boot(auto_boot),
        .boot_addr(boot_addr),
        // Cartridge information outputs
        .rom_type(rom_type),
        .rom_size(rom_size),
        .rom_checksum(rom_checksum),
        .rom_version(rom_version),
        .rom_date(rom_date),
        .rom_title(rom_title),
        // Plus-specific outputs - now used for any cartridge validation
        .plus_bios_valid(plus_bios_valid),
        .plus_bios_checksum(plus_bios_checksum),
        .plus_bios_version(plus_bios_version)
    );

endmodule 