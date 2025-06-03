module ASIC_registers
(
    input         clk_sys,
    input         reset,
    input         plus_mode,      // Plus mode enable
    
    // CPU interface
    input  [15:0] cpu_addr,      // CPU address bus
    input   [7:0] cpu_data_in,   // CPU data input
    input         cpu_wr,        // CPU write strobe
    input         cpu_rd,        // CPU read strobe
    output reg [7:0] cpu_data_out,  // CPU data output
    output reg        cpu_data_out_en,  // CPU data output enable
    output reg [7:0]  asic_data_out,  // ASIC data output
    output reg        asic_data_out_en,  // ASIC data output enable
    output reg [7:0]  ppi_port_a,
    output reg [7:0]  ppi_port_b,
    output reg [7:0]  ppi_port_c,
    output reg [7:0]  crtc_regs_reg[0:31],
    output reg [7:0]  crtc_reg_select,
    output reg        acid_unlocked,
    
    // Configuration outputs
    output reg [7:0] ram_config,
    output reg [7:0] rom_config,
    output reg [7:0] rom_select,
    output reg [4:0] current_pen,
    output reg [7:0] pen_registers,
    output reg [7:0] mrer
);

    // ASIC 16K memory (mapped 4000h-7FFFh)
    reg [7:0] asic_memory[0:16383];  // 16K memory for ASIC
    wire [13:0] asic_mem_offset = cpu_addr[13:0]; // Offset for 4000h-7FFFh
    wire asic_mem_access = (cpu_addr[15:14] == 2'b01);  // 16K at 4000-7FFF
    wire asic_mem_wr = asic_mem_access && cpu_wr;
    wire asic_mem_rd = asic_mem_access && cpu_rd;

    // Register map offsets (relative to 4000h)
    localparam SPRITE_IMG_BASE = 14'h0000; // 4000h
    localparam SPRITE_IMG_SIZE = 16'h100;  // 256 bytes per sprite
    localparam SPRITE_COUNT    = 16;
    localparam SPRITE_XY_BASE  = 14'h2000; // 6000h
    localparam SPRITE_XY_SIZE  = 8'h08;    // 8 bytes per sprite (X, Y, M, unused)
    localparam PALETTE_BASE    = 14'h2400; // 6400h
    localparam PALETTE_SIZE    = 8'h40;    // 64 bytes
    localparam PRI_ADDR        = 14'h2800; // 6800h
    localparam SPLT_ADDR       = 14'h2801; // 6801h
    localparam SSA_ADDR        = 14'h2802; // 6802h (2 bytes)
    localparam SSCR_ADDR       = 14'h2804; // 6804h
    localparam ADC_BASE        = 14'h2808; // 6808h (8 bytes)
    localparam DMA_BASE        = 14'h2C00; // 6C00h
    localparam DMA_SIZE        = 8'h10;    // 16 bytes

    // I/O space registers (separate from asic_memory)
    reg [7:0] mrer_reg;         // Memory and ROM Enable Register
    reg [7:0] rmr2_reg;         // RMR2 register
    reg [7:0] ram_map_reg;      // RAM mapping register
    reg [7:0] rom_sel_reg;      // ROM select register
    reg [4:0] palette_ptr;      // Palette pointer
    reg [4:0] palette_mem[0:15]; // Palette memory (16 entries)
    reg [7:0] crtc_select_reg;  // CRTC register select
    reg [7:0] crtc_regs[0:31];  // CRTC registers
    reg [7:0] acid_seq[0:15];   // ACID unlock sequence
    reg [4:0] acid_pos;         // ACID unlock position
    reg       acid_unlock_reg;  // ACID unlocked flag
    reg [7:0] crtc_select_prev; // Previous CRTC select value for change detection
    reg [7:0] rom_config_prev;  // Previous ROM config value for change detection
    reg [7:0] rom_sel_prev;     // Previous ROM select value for change detection
    reg [7:0] rmr2_prev;        // Previous RMR2 value for change detection
    reg [7:0] crtc_data_prev;   // Previous CRTC data value for change detection
    reg [7:0] ram_map_prev;     // Previous RAM map value for change detection
    reg [7:0] pen_ink_prev;     // Previous pen/ink value for change detection
    reg [13:0] unused_mem_addr_prev; // Previous unused memory address for change detection
    reg [7:0] pen_ink_ports_prev[0:16]; // Previous values for each pen/ink port
    reg [4:0] pen_ink_state_prev; // Previous pen/ink state

    // Sprite palette memory (2 bytes per entry: RGB format)
    reg [7:0] sprite_palette[0:31][0:1];  // 32 entries, 2 bytes each
    reg [7:0] sprite_palette_prev[0:31][0:1];  // For change detection

    // RGB color mapping for hardware color indices
    function [17:0] get_rgb_for_index;
        input [4:0] index;
        begin
            case (index)
                5'd0:  get_rgb_for_index = {6'h6, 6'h6, 6'h6};  // White
                5'd1:  get_rgb_for_index = {6'h6, 6'h6, 6'h6};  // White
                5'd2:  get_rgb_for_index = {6'h0, 6'hF, 6'h6};  // Sea Green
                5'd3:  get_rgb_for_index = {6'hF, 6'hF, 6'h6};  // Pastel Yellow
                5'd4:  get_rgb_for_index = {6'h0, 6'h0, 6'h6};  // Blue
                5'd5:  get_rgb_for_index = {6'hF, 6'h0, 6'h6};  // Purple
                5'd6:  get_rgb_for_index = {6'h0, 6'h6, 6'h6};  // Cyan
                5'd7:  get_rgb_for_index = {6'hF, 6'h6, 6'h6};  // Pink
                5'd8:  get_rgb_for_index = {6'hF, 6'h0, 6'h6};  // Purple
                5'd9:  get_rgb_for_index = {6'hF, 6'hF, 6'h6};  // Pastel Yellow
                5'd10: get_rgb_for_index = {6'hF, 6'hF, 6'h0};  // Bright Yellow
                5'd11: get_rgb_for_index = {6'hF, 6'hF, 6'hF};  // Bright White
                5'd12: get_rgb_for_index = {6'hF, 6'h0, 6'h0};  // Bright Red
                5'd13: get_rgb_for_index = {6'hF, 6'h0, 6'hF};  // Bright Magenta
                5'd14: get_rgb_for_index = {6'hF, 6'h6, 6'h0};  // Orange
                5'd15: get_rgb_for_index = {6'hF, 6'h6, 6'hF};  // Pastel Magenta
                5'd16: get_rgb_for_index = {6'h0, 6'h0, 6'h6};  // Blue
                5'd17: get_rgb_for_index = {6'h0, 6'hF, 6'h6};  // Sea Green
                5'd18: get_rgb_for_index = {6'h0, 6'hF, 6'h0};  // Bright Green
                5'd19: get_rgb_for_index = {6'h0, 6'hF, 6'hF};  // Bright Cyan
                5'd20: get_rgb_for_index = {6'h0, 6'h0, 6'h0};  // Black
                5'd21: get_rgb_for_index = {6'h0, 6'h0, 6'hF};  // Bright Blue
                5'd22: get_rgb_for_index = {6'h0, 6'h6, 6'h0};  // Green
                5'd23: get_rgb_for_index = {6'h0, 6'h6, 6'hF};  // Sky Blue
                5'd24: get_rgb_for_index = {6'h6, 6'h0, 6'h6};  // Magenta
                5'd25: get_rgb_for_index = {6'h6, 6'hF, 6'h6};  // Pastel Green
                5'd26: get_rgb_for_index = {6'h6, 6'hF, 6'h0};  // Lime
                5'd27: get_rgb_for_index = {6'h6, 6'hF, 6'hF};  // Pastel Cyan
                5'd28: get_rgb_for_index = {6'h6, 6'h0, 6'h0};  // Red
                5'd29: get_rgb_for_index = {6'h6, 6'h0, 6'hF};  // Mauve
                5'd30: get_rgb_for_index = {6'h6, 6'h6, 6'h0};  // Yellow
                5'd31: get_rgb_for_index = {6'h6, 6'h6, 6'hF};  // Pastel Blue
                default: get_rgb_for_index = {6'h0, 6'h0, 6'h0}; // Black
            endcase
        end
    endfunction

    // Address decode
    wire reg_wr = cpu_wr && (cpu_addr[15:8] == 8'h7F);
    wire reg_rd = cpu_rd && (cpu_addr[15:8] == 8'h7F);
    wire rom_wr = cpu_wr && (cpu_addr[15:8] == 8'hDF);
    wire ppi_wr = cpu_wr && (cpu_addr[15:8] == 8'hF7);
    wire ppi_rd = cpu_rd && (cpu_addr[15:8] == 8'hF7);
    wire plus_wr = cpu_wr && (cpu_addr == 16'hEF7F);  // Plus control register
    wire crtc_select_wr = cpu_wr && (cpu_addr[15:8] == 8'hBC) && (cpu_addr[7:0] == 8'h00);  // CRTC register select
    wire crtc_data_wr = cpu_wr && (cpu_addr[15:8] == 8'hBD) && (cpu_addr[7:0] == 8'h00);    // CRTC register data
    wire fdc_wr = cpu_wr && (cpu_addr[15:8] == 8'hFA);  // FDC control
    wire f600_wr = cpu_wr && (cpu_addr == 16'hF600);  // Add F600 port write

    // DMA control registers
    reg [7:0] dma_channel_ptr[0:2];    // DMA channel pointers
    reg [7:0] dma_channel_prescalar[0:2]; // DMA channel prescalars
    reg [7:0] dcsr_reg;                // DMA Control and Status Register
    reg [7:0] dcsr_prev;               // For change detection

    // DMA Control and Status Register bits
    localparam DCSR_RASTER_INT = 7;    // Bit 7: Raster Interrupt
    localparam DCSR_DMA0_INT   = 6;    // Bit 6: DMA Channel 0 Interrupt
    localparam DCSR_DMA1_INT   = 5;    // Bit 5: DMA Channel 1 Interrupt
    localparam DCSR_DMA2_INT   = 4;    // Bit 4: DMA Channel 2 Interrupt
    localparam DCSR_DMA2_EN    = 2;    // Bit 2: DMA Channel 2 Enable
    localparam DCSR_DMA1_EN    = 1;    // Bit 1: DMA Channel 1 Enable
    localparam DCSR_DMA0_EN    = 0;    // Bit 0: DMA Channel 0 Enable

    // DMA opcode function bits
    localparam DMA_NOP_LOOP_INT_STOP = 2;  // Bit 2: Nop/loop/Int/Stop instruction
    localparam DMA_REPEAT_N         = 1;   // Bit 1: Repeat N instruction
    localparam DMA_PAUSE           = 0;    // Bit 0: Pause instruction

    // Handle register writes
    always @(posedge clk_sys) begin
        if (reset) begin
            // Clear all memory
            for (int i = 0; i < 16384; i++) asic_memory[i] = 8'h00;
            // Initialize I/O registers
            mrer_reg <= 8'h00;
            rmr2_reg <= 8'h00;
            ram_map_reg <= 8'h00;
            rom_sel_reg <= 8'h00;
            palette_ptr <= 5'h00;
            for (int i = 0; i < 16; i++) palette_mem[i] <= 5'h00;
            crtc_select_reg <= 8'h00;
            for (int i = 0; i < 32; i++) crtc_regs[i] <= 8'h00;
            acid_pos <= 5'h00;
            acid_unlock_reg <= 1'b0;
            // Initialize ACID sequence
            acid_seq[0] <= 8'haa;
            acid_seq[1] <= 8'h00;
            acid_seq[2] <= 8'hff;
            acid_seq[3] <= 8'h77;
            acid_seq[4] <= 8'hb3;
            acid_seq[5] <= 8'h51;
            acid_seq[6] <= 8'ha8;
            acid_seq[7] <= 8'hd4;
            acid_seq[8] <= 8'h62;
            acid_seq[9] <= 8'h39;
            acid_seq[10] <= 8'h9c;
            acid_seq[11] <= 8'h46;
            acid_seq[12] <= 8'h2b;
            acid_seq[13] <= 8'h15;
            acid_seq[14] <= 8'h8a;
            acid_seq[15] <= 8'hcd;
            // Initialize other registers
            ppi_port_a <= 8'h00;
            ppi_port_b <= 8'h00;
            ppi_port_c <= 8'h00;
            crtc_select_prev <= 8'h00;
            rom_config_prev <= 8'h00;
            rom_sel_prev <= 8'h00;
            rmr2_prev <= 8'h00;
            crtc_data_prev <= 8'h00;
            ram_map_prev <= 8'h00;
            pen_ink_prev <= 8'h00;
            unused_mem_addr_prev <= 14'h0000;
            for (int i = 0; i < 16; i++) pen_ink_ports_prev[i] <= 8'h00;
            pen_ink_state_prev <= 5'h00;
        end else begin
            // CRTC register handling
            if (crtc_select_wr) begin
                crtc_select_reg <= cpu_data_in;
                //$display("ASIC: OUT on port bc%02x, val=%02x", cpu_data_in, cpu_data_in);

                // Check for ACID unlock sequence only if value changed
                if (!acid_unlock_reg && cpu_data_in != crtc_select_prev) begin
                    if (cpu_data_in == acid_seq[acid_pos]) begin
                        acid_pos <= acid_pos + 1'd1;
                        if (acid_pos == 4'd15) begin
                            acid_unlock_reg <= 1'b1;
                            $display("ASIC: ACID unlocked!");
                        end
                    end else begin
                        acid_pos <= 0;
                    end
                end
                crtc_select_prev <= cpu_data_in;
            end

            if (crtc_data_wr) begin
                // Only write to CRTC register if ACID is unlocked or it's a standard CRTC register (0-15)
                if (acid_unlock_reg || crtc_select_reg < 16) begin
                    if (cpu_data_in != crtc_data_prev) begin
                        crtc_regs[crtc_select_reg] <= cpu_data_in;
                        //$display("ASIC: CRTC write to register %d: %d", crtc_select_reg, cpu_data_in);
                        crtc_data_prev <= cpu_data_in;
                    end
                end else begin
                    //$display("ASIC: Ignoring CRTC write to register %d (ACID locked)", crtc_select_reg);
                end
            end

            // I/O space register writes
            if (reg_wr) begin
                case (cpu_addr[7:0])
                    8'hB8: begin
                        // Register paging control
                        if (cpu_data_in[7] && cpu_data_in != rmr2_prev) begin
                            rmr2_reg <= cpu_data_in;
                            $display("ASIC: RMR2: Low bank rom = 0x0000 - page %d", cpu_data_in[2:0]);
                            rmr2_prev <= cpu_data_in;
                        end
                    end

                    // RAM configuration registers
                    8'hC0, 8'hC1, 8'hC2, 8'hC3, 8'hC4, 8'hC5, 8'hC6, 8'hC7: begin
                        if (cpu_addr[7:0] != ram_map_prev) begin
                            ram_map_reg <= cpu_addr[7:0];
                            $display("ASIC: RAM config %02x: %dK RAM at 0x0000", cpu_addr[7:0], (((cpu_addr[3:0] - 8'hC0) & 8'h0F) + 1) * 64);
                            ram_map_prev <= cpu_addr[7:0];
                        end
                    end
                    
                    8'h89: begin
                        if (cpu_data_in != rom_config_prev) begin
                            mrer_reg <= cpu_data_in;
                            $display("ASIC: ROM config: %02x", cpu_data_in);
                            rom_config_prev <= cpu_data_in;
                        end
                    end

                    8'h00, 8'h01, 8'h02, 8'h03, 8'h04, 8'h05, 8'h06, 8'h07,
                    8'h08, 8'h09, 8'h0A, 8'h0B, 8'h0C, 8'h0D, 8'h0E, 8'h0F,
                    8'h10: begin
                        // Pen and ink register (0x7F00-0x7F10)
                        if (cpu_data_in != pen_ink_ports_prev[cpu_addr[4:0]]) begin
                            if (cpu_data_in[7:6] == 2'b00) begin
                                // Pen selection register - only write if value is different
                                if (palette_ptr != cpu_data_in[4:0]) begin
                                    palette_ptr <= cpu_data_in[4:0];
                                    //$display("ASIC: Set pen value to %d (port 0x7F%02x)", cpu_data_in[4:0], cpu_addr[7:0]);
                                end
                            end else begin
                                // Ink value register - only write if value is different
                                if (palette_mem[palette_ptr] != cpu_data_in[4:0]) begin
                                    palette_mem[palette_ptr] <= cpu_data_in[4:0];
                                    //$display("ASIC: Set ink value %d to %d (port 0x7F%02x)", palette_ptr, cpu_data_in[4:0], cpu_addr[7:0]);
                                end
                            end
                            pen_ink_ports_prev[cpu_addr[4:0]] <= cpu_data_in;
                            pen_ink_state_prev <= cpu_data_in[7:6];
                        end
                    end

                    default: begin
                        // Write unknown port values to ASIC memory for debugging
                        if (cpu_addr[7:0] >= 8'h80 && cpu_addr[7:0] <= 8'hFF) begin
                            // Only write if value has changed
                            if (asic_memory[14'h3F00 + cpu_addr[7:0]] != cpu_data_in) begin
                                asic_memory[14'h3F00 + cpu_addr[7:0]] <= cpu_data_in;
                                $display("ASIC: Write to ASIC memory at 0x%04x: %02x (from port 0x7F%02x)", 
                                        14'h3F00 + cpu_addr[7:0], cpu_data_in, cpu_addr[7:0]);
                            end
                        end else begin
                            $display("ASIC: Unhandled port write to 0x7F%02x: value=%02x", cpu_addr[7:0], cpu_data_in);
                        end
                    end
                endcase
            end
            
            if (rom_wr && cpu_addr[7:0] == 8'h00) begin
                if (cpu_data_in != rom_sel_prev) begin
                    rom_sel_reg <= cpu_data_in;
                    $display("ASIC: ROM select: %d", cpu_data_in);
                    rom_sel_prev <= cpu_data_in;
                end
            end

            // ASIC memory write (4000h-7FFFh)
            if (asic_mem_wr) begin
                // Write only to writable registers/areas
                if (asic_mem_offset < 14'h1000) begin
                    // Sprite image data (4000h-4FFFh) - mask with 0x0F
                    asic_memory[asic_mem_offset] <= cpu_data_in & 8'h0F;
                    $display("ASIC: Write to sprite image data at 0x%04x: %02x (masked to %02x)", 
                            asic_mem_offset + 14'h4000, cpu_data_in, cpu_data_in & 8'h0F);
                end
                else if (asic_mem_offset >= SPRITE_XY_BASE && asic_mem_offset < SPRITE_XY_BASE + 8*SPRITE_COUNT) begin
                    // Sprite XY/M registers (6000h-607Fh)
                    if ((asic_mem_offset & 14'h0007) != 14'h0005 && (asic_mem_offset & 14'h0007) != 14'h0007) begin
                        // Only write to X, Y, and M registers (not unused areas)
                        asic_memory[asic_mem_offset] <= cpu_data_in;
                        $display("ASIC: Write to sprite %d %s at 0x%04x: %02x", 
                            (asic_mem_offset - SPRITE_XY_BASE) >> 3,
                            ((asic_mem_offset & 14'h0007) == 14'h0004) ? "magnification" :
                            ((asic_mem_offset & 14'h0007) < 14'h0002) ? "X position" : "Y position",
                            asic_mem_offset + 14'h4000, cpu_data_in);
                    end
                end
                else if (asic_mem_offset >= PALETTE_BASE && asic_mem_offset < PALETTE_BASE + PALETTE_SIZE) begin
                    // Sprite palette registers (6400h-643Fh)
                    reg [4:0] palette_index = (asic_mem_offset - PALETTE_BASE) >> 1;
                    reg [0:0] palette_offset = (asic_mem_offset - PALETTE_BASE) & 1'b1;
                    
                    if (cpu_data_in != sprite_palette_prev[palette_index][palette_offset]) begin
                        sprite_palette[palette_index][palette_offset] <= cpu_data_in;
                        sprite_palette_prev[palette_index][palette_offset] <= cpu_data_in;
                        
                        // If writing to offset 0, update both bytes with RGB values
                        if (palette_offset == 0) begin
                            reg [17:0] rgb = get_rgb_for_index(cpu_data_in[4:0]);
                            sprite_palette[palette_index][0] <= {rgb[17:12], rgb[5:0]};  // RB
                            sprite_palette[palette_index][1] <= rgb[11:6];               // G
                        end
                        
                        $display("ASIC: Write to sprite palette entry %d offset %d: %02x", 
                                palette_index, palette_offset, cpu_data_in);
                    end
                end
                else if (asic_mem_offset == PRI_ADDR) begin
                    // PRI register (6800h) - write only
                    asic_memory[asic_mem_offset] <= cpu_data_in;
                    $display("ASIC: Write to interrupt raster line (PRI): %02x", cpu_data_in);
                end
                else if (asic_mem_offset == SPLT_ADDR) begin
                    // SPLT register (6801h) - write only
                    asic_memory[asic_mem_offset] <= cpu_data_in;
                    $display("ASIC: Write to screen split line (SPLT): %02x", cpu_data_in);
                end
                else if (asic_mem_offset >= SSA_ADDR && asic_mem_offset < SSA_ADDR + 2) begin
                    // SSA register (6802h-6803h) - write only
                    asic_memory[asic_mem_offset] <= cpu_data_in;
                    $display("ASIC: Write to screen split address at offset %d: %02x", asic_mem_offset - SSA_ADDR, cpu_data_in);
                end
                else if (asic_mem_offset == SSCR_ADDR) begin
                    // SSCR register (6804h) - write only
                    asic_memory[asic_mem_offset] <= cpu_data_in;
                    $display("ASIC: Write to soft scroll (SSCR): %02x", cpu_data_in);
                end
                else if (asic_mem_offset == 14'h2805) begin
                    // Interrupt vector (6805h) - write only
                    asic_memory[asic_mem_offset] <= cpu_data_in;
                    $display("ASIC: Write to interrupt vector: %02x", cpu_data_in);
                end
                // 6806h and 6807h are write-only with no effect
                else if (asic_mem_offset == 14'h2806 || asic_mem_offset == 14'h2807) begin
                    // These registers are write-only with no effect
                    $display("ASIC: Write to unused register at 0x%04x: %02x", asic_mem_offset + 14'h4000, cpu_data_in);
                end
                else if (asic_mem_offset >= DMA_BASE && asic_mem_offset < DMA_BASE + DMA_SIZE) begin
                    // DMA registers (6C00h-6C0Fh)
                    reg [1:0] channel = (asic_mem_offset - DMA_BASE) >> 2;  // 0, 1, or 2
                    reg [1:0] offset = (asic_mem_offset - DMA_BASE) & 2'h3; // 0, 1, 2, or 3
                    
                    if (offset < 3) begin  // Only handle offsets 0, 1, and 2
                        if (offset == 0 || offset == 1) begin
                            // Set DMA channel pointer
                            dma_channel_ptr[channel] <= cpu_data_in;
                            $display("ASIC: Write to DMA channel %d pointer offset %d: %02x", 
                                    channel, offset, cpu_data_in);
                        end
                        else if (offset == 2) begin
                            // Set channel prescalar
                            dma_channel_prescalar[channel] <= cpu_data_in;
                            $display("ASIC: Write to DMA channel %d prescalar: %02x", 
                                    channel, cpu_data_in);
                        end
                    end
                    else if (asic_mem_offset == DMA_BASE + 15) begin
                        // DCSR register (6C0Fh)
                        if (cpu_data_in != dcsr_prev) begin
                            dcsr_reg <= cpu_data_in;
                            dcsr_prev <= cpu_data_in;
                            $display("ASIC: Write to DCSR: %02x (Raster Int: %b, DMA Ints: %b%b%b, DMA Enables: %b%b%b)",
                                    cpu_data_in,
                                    cpu_data_in[DCSR_RASTER_INT],
                                    cpu_data_in[DCSR_DMA0_INT],
                                    cpu_data_in[DCSR_DMA1_INT],
                                    cpu_data_in[DCSR_DMA2_INT],
                                    cpu_data_in[DCSR_DMA0_EN],
                                    cpu_data_in[DCSR_DMA1_EN],
                                    cpu_data_in[DCSR_DMA2_EN]);
                        end
                    end
                end
                else if (asic_mem_offset >= 14'h3F00 && asic_mem_offset <= 14'h3F10) begin
                    // Handle palette writes in 0x7F00-0x7F10 range
                    if (cpu_data_in[7:6] == 2'b00) begin
                        // Pen selection register
                        palette_ptr <= cpu_data_in[4:0];
                        //$display("ASIC: Set pen value to %d (port 0x7F%02x)", cpu_data_in[4:0], asic_mem_offset[7:0]);
                    end else begin
                        // Ink value register
                        palette_mem[palette_ptr] <= cpu_data_in[4:0];
                        //$display("ASIC: Set ink value %d to %d (port 0x7F%02x)", palette_ptr, cpu_data_in[4:0], asic_mem_offset[7:0]);
                    end
                end
                else begin
                    // Only display debug message if value or address has changed
                    if (cpu_data_in != pen_ink_prev || asic_mem_offset != unused_mem_addr_prev) begin
                        $display("ASIC: Write to unused memory at 0x%04x: %02x", asic_mem_offset + 14'h4000, cpu_data_in);
                        pen_ink_prev <= cpu_data_in;
                        unused_mem_addr_prev <= asic_mem_offset;
                        asic_memory[asic_mem_offset] <= cpu_data_in;
                    end
                end
            end
        end
    end

    // Handle register reads
    always @(posedge clk_sys) begin
        cpu_data_out = 8'hFF;
        cpu_data_out_en = 0;
        asic_data_out = 8'hFF;
        asic_data_out_en = 0;

        if (asic_mem_rd) begin
            if (asic_mem_offset < 14'h1000) begin
                // Sprite image data (4000h-4FFFh) - mask with 0x0F
                cpu_data_out = asic_memory[asic_mem_offset] & 8'h0F;
                cpu_data_out_en = 1;
            end
            else if (asic_mem_offset >= SPRITE_XY_BASE && asic_mem_offset < SPRITE_XY_BASE + 8*SPRITE_COUNT) begin
                // Sprite XY/M registers (6000h-607Fh)
                reg [7:0] sprite_data;
                reg [2:0] reg_offset = asic_mem_offset[2:0];
                
                if (reg_offset < 4) begin
                    // X and Y coordinates (offsets 0-3)
                    sprite_data = asic_memory[asic_mem_offset];
                    
                    if (reg_offset == 1) begin
                        // High byte of X coordinate
                        if ((sprite_data & 8'h03) == 8'h03)
                            sprite_data = 8'hFF;
                        else
                            sprite_data = sprite_data & 8'h03;
                    end
                    else if (reg_offset == 3) begin
                        // High byte of Y coordinate
                        if ((sprite_data & 8'h01) == 8'h01)
                            sprite_data = 8'hFF;
                        else
                            sprite_data = sprite_data & 8'h01;
                    end
                end
                else begin
                    // Magnification registers (offsets 4-7) mirror offsets 0-3
                    sprite_data = asic_memory[SPRITE_XY_BASE + ((asic_mem_offset - SPRITE_XY_BASE) & 14'hFFF8) + (reg_offset - 4)];
                end
                
                cpu_data_out = sprite_data;
                cpu_data_out_en = 1;
            end
            else if (asic_mem_offset >= PALETTE_BASE && asic_mem_offset < PALETTE_BASE + PALETTE_SIZE) begin
                // Sprite palette registers (6400h-643Fh)
                reg [4:0] palette_index = (asic_mem_offset - PALETTE_BASE) >> 1;
                reg [0:0] palette_offset = (asic_mem_offset - PALETTE_BASE) & 1'b1;
                
                if (palette_offset == 0) begin
                    // Offset 0: Return value as written
                    cpu_data_out = sprite_palette[palette_index][0];
                end else begin
                    // Offset 1: Return value & 0x0F
                    cpu_data_out = sprite_palette[palette_index][1] & 8'h0F;
                end
                cpu_data_out_en = 1;
            end
            else if (asic_mem_offset >= PRI_ADDR && asic_mem_offset <= 14'h2807) begin
                // PRI, SPLT, SSA, SSCR, and misc registers
                cpu_data_out = (asic_mem_offset >= PRI_ADDR && asic_mem_offset <= 14'h2807) ? 8'hFF : asic_memory[asic_mem_offset];
                cpu_data_out_en = 1;
            end
            else if (asic_mem_offset >= DMA_BASE && asic_mem_offset < DMA_BASE + DMA_SIZE) begin
                // DMA registers (6C00h-6C0Fh)
                if (asic_mem_offset == DMA_BASE + 15) begin
                    // DCSR register (6C0Fh)
                    cpu_data_out = dcsr_reg;
                end
                else begin
                    // All other DMA registers return DCSR value
                    cpu_data_out = dcsr_reg;
                end
                cpu_data_out_en = 1;
            end
        end
        else if (reg_rd) begin
            case (cpu_addr[7:0])
                8'h00: begin cpu_data_out = ppi_port_a; cpu_data_out_en = 1; end
                8'h01: begin cpu_data_out = ppi_port_b; cpu_data_out_en = 1; end
                8'h02: begin cpu_data_out = ppi_port_c; cpu_data_out_en = 1; end
                8'h89: begin cpu_data_out = mrer_reg; cpu_data_out_en = 1; end
                8'hC0: begin cpu_data_out = ram_map_reg; cpu_data_out_en = 1; end
                8'h10: begin 
                    cpu_data_out = {2'b00, palette_ptr[4] ? palette_mem[palette_ptr[3:0]] : palette_ptr};
                    cpu_data_out_en = 1;
                end
            endcase
        end
        else if (crtc_select_wr) begin
            asic_data_out = crtc_select_reg;
            asic_data_out_en = 1;
        end
        else if (crtc_data_wr) begin
            asic_data_out = crtc_regs[crtc_select_reg];
            asic_data_out_en = 1;
        end
    end

    // Output assignments
    always @(posedge clk_sys) begin
        ram_config <= ram_map_reg;
        rom_config <= mrer_reg;
        rom_select <= rom_sel_reg;
        current_pen <= palette_ptr;
        pen_registers <= palette_mem[palette_ptr];
        mrer <= mrer_reg;
        crtc_reg_select <= crtc_select_reg;
        crtc_regs_reg <= crtc_regs;
        acid_unlocked <= acid_unlock_reg;
    end

endmodule 