module GX4000_registers
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
    output reg [7:0] ppi_control,
    output reg [4:0] current_pen,
    output reg [7:0] pen_registers,
    output reg [7:0] mrer,

    // Add breakpoint control
    output reg [31:0] break_point,  // Breakpoint address
    input      [31:0] current_pc    // Current program counter
);

    // Internal registers
    reg [7:0] asic_registers[0:31];  // 32 registers for pen/ink values
    reg [4:0] current_pen_reg;       // Current pen selection
    reg [7:0] ram_config_reg;        // RAM configuration register
    reg [7:0] rom_config_reg;        // ROM configuration register
    reg [7:0] rom_select_reg;        // ROM select register
    reg [7:0] ppi_control_reg;       // PPI control register
    reg [7:0] mrer_reg;             // Memory and ROM Enable Register
    reg [2:0] bit_to_modify;        // Bit to modify in PPI port C

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

    // Debounce registers
    reg [15:0] last_addr;
    reg [7:0] last_data;
    reg last_wr;
    reg last_crtc_select;
    reg last_crtc_data;
    reg last_reg_wr;
    reg last_rom_wr;
    reg last_ppi_wr;
    reg last_plus_wr;
    reg last_acid_wr;
    reg last_plus_data;  // Add debounce for Plus control data
    reg last_fdc_wr;     // Add debounce for FDC write
    reg last_fdc_data;   // Add debounce for FDC data
    reg last_f600_wr;    // Add F600 debounce
    reg last_f600_data;  // Add F600 data debounce

    // Edge detection registers
    reg crtc_select_prev;
    reg crtc_data_prev;
    reg reg_wr_prev;
    reg rom_wr_prev;
    reg ppi_wr_prev;
    reg plus_wr_prev;
    reg fdc_wr_prev;     // Add edge detection for FDC write
    reg f600_wr_prev;    // Add F600 edge detection

    // ACID unlock sequence
    reg [7:0] acid_unlock_seq[0:15] = '{
        8'haa, 8'h00, 8'hff, 8'h77, 8'hb3, 8'h51, 8'ha8, 8'hd4,
        8'h62, 8'h39, 8'h9c, 8'h46, 8'h2b, 8'h15, 8'h8a, 8'hcd
    };
    reg [3:0] acid_unlock_pos = 0;

    // Handle register writes
    always @(posedge clk_sys) begin
        if (reset) begin
            current_pen_reg <= 5'd0;
            for (int i = 0; i < 32; i++) asic_registers[i] <= 8'h00;
            ram_config_reg <= 8'h00;
            rom_config_reg <= 8'h00;
            rom_select_reg <= 8'h00;
            ppi_control_reg <= 8'h00;
            mrer_reg <= 8'h00;
            crtc_reg_select <= 8'h00;
            for (int i = 0; i < 32; i++) crtc_regs_reg[i] <= 8'h00;
            last_addr <= 16'h0000;
            last_data <= 8'h00;
            last_wr <= 1'b0;
            last_crtc_select <= 1'b0;
            last_crtc_data <= 1'b0;
            last_reg_wr <= 1'b0;
            last_rom_wr <= 1'b0;
            last_ppi_wr <= 1'b0;
            last_plus_wr <= 1'b0;
            last_acid_wr <= 1'b0;
            last_plus_data <= 8'h00;
            acid_unlock_pos <= 0;
            acid_unlocked <= 0;
            crtc_select_prev <= 1'b0;
            crtc_data_prev <= 1'b0;
            reg_wr_prev <= 1'b0;
            rom_wr_prev <= 1'b0;
            ppi_wr_prev <= 1'b0;
            plus_wr_prev <= 1'b0;
            fdc_wr_prev <= 1'b0;
            last_fdc_wr <= 1'b0;
            last_fdc_data <= 8'h00;
            ppi_port_a <= 8'h00;
            ppi_port_b <= 8'h00;
            ppi_port_c <= 8'h00;
            break_point <= 32'hFFFFFFFF;  // Initialize to no breakpoint
            last_f600_wr <= 1'b0;
            last_f600_data <= 8'h00;
            f600_wr_prev <= 1'b0;
        end else begin
            // Store previous states for edge detection
            crtc_select_prev <= crtc_select_wr;
            crtc_data_prev <= crtc_data_wr;
            reg_wr_prev <= reg_wr;
            rom_wr_prev <= rom_wr;
            ppi_wr_prev <= ppi_wr;
            plus_wr_prev <= plus_wr;
            fdc_wr_prev <= fdc_wr;
            f600_wr_prev <= f600_wr;

            // Store current values for debouncing
            last_addr <= cpu_addr;
            last_data <= cpu_data_in;
            last_wr <= cpu_wr;
            last_crtc_select <= crtc_select_wr;
            last_crtc_data <= crtc_data_wr;
            last_plus_data <= cpu_data_in;  // Store Plus control data
            last_fdc_data <= cpu_data_in;
            last_f600_data <= cpu_data_in;

            // CRTC register handling with proper debouncing
            if (crtc_select_wr && !last_crtc_select) begin
                crtc_reg_select <= cpu_data_in;
                $display("ASIC: OUT on port bc%02x, val=%02x", cpu_data_in, cpu_data_in);

                // Check for ACID unlock sequence
                if (!acid_unlocked) begin
                    if (cpu_data_in == acid_unlock_seq[acid_unlock_pos]) begin
                        acid_unlock_pos <= acid_unlock_pos + 1'd1;
                        if (acid_unlock_pos == 4'd16) begin
                            acid_unlocked <= 1'b1;
                            $display("ASIC: ACID unlocked!");
                        end
                    end else begin
                        acid_unlock_pos <= 0;
                    end
                end
            end

            if (crtc_data_wr && !last_crtc_data) begin
                // Only write to CRTC register if ACID is unlocked or it's a standard CRTC register (0-15)
                if (acid_unlocked || crtc_reg_select < 16) begin
                    crtc_regs_reg[crtc_reg_select] <= cpu_data_in;
                    $display("ASIC: OUT on port bd%02x, val=%02x", crtc_reg_select, cpu_data_in);
                    $display("ASIC: CRTC write to register %d: %d", crtc_reg_select, cpu_data_in);
                end else begin
                    $display("ASIC: Ignoring CRTC write to register %d (ACID locked)", crtc_reg_select);
                end
            end

            // Only process write if data has changed (allow repeated addresses)
            if (reg_wr && !reg_wr_prev) begin
                case (cpu_addr[7:0])
                    8'hB8: begin
                        // Register paging control
                        $display("ASIC: OUT on port 7fb8, val=%02x", cpu_data_in);
                        $display("ASIC: Register page %s", cpu_data_in[7] ? "on" : "off");
                        if (cpu_data_in[7]) begin
                            // When paging is enabled, update MRER
                            mrer_reg <= cpu_data_in;
                            $display("ASIC: RMR2: Low bank rom = 0x0000 - page %d", cpu_data_in[2:0]);
                        end
                    end

                    8'hC0: begin
                        // RAM configuration register
                        ram_config_reg <= cpu_data_in;
                        $display("ASIC: OUT on port 7fc0, val=%02x", cpu_data_in);
                        $display("ASIC: RAM config: %02x", cpu_data_in);
                    end
                    
                    8'h89: begin
                        // Memory and ROM Enable Register (MRER)
                        mrer_reg <= cpu_data_in;
                        $display("ASIC: OUT on port 7f89, val=%02x", cpu_data_in);
                        $display("ASIC: ROM config: %02x", cpu_data_in);
                        $display("ASIC: MRER: %02x", cpu_data_in);
                    end
                    
                    8'h10: begin
                        if (cpu_data_in[7:6] == 2'b00) begin
                            // Pen selection register
                            current_pen_reg <= cpu_data_in[4:0];
                            $display("ASIC: OUT on port 7f10, val=%02x", cpu_data_in);
                            $display("ASIC: Set pen value to %d", cpu_data_in[4:0]);
                        end else begin
                            // Ink value register - decode the value
                            // The ink value is the lower 5 bits of the data
                            asic_registers[current_pen_reg] <= cpu_data_in[4:0];
                            $display("ASIC: OUT on port 7f10, val=%02x", cpu_data_in);
                            $display("ASIC: Set ink value %d to %d", current_pen_reg, cpu_data_in[4:0]);
                        end
                    end
                    
                    default: begin
                        if (cpu_addr[7:4] == 4'h0) begin
                            if (cpu_data_in[7:6] == 2'b00) begin
                                // Pen selection register
                                current_pen_reg <= cpu_data_in[4:0];
                                $display("ASIC: OUT on port 7f%02x, val=%02x", cpu_addr[7:0], cpu_data_in);
                                $display("ASIC: Set pen value to %d", cpu_data_in[4:0]);
                            end else begin
                                // Ink value register - decode the value
                                // The ink value is the lower 5 bits of the data
                                asic_registers[current_pen_reg] <= cpu_data_in[4:0];
                                $display("ASIC: OUT on port 7f%02x, val=%02x", cpu_addr[7:0], cpu_data_in);
                                $display("ASIC: Set ink value %d to %d", current_pen_reg, cpu_data_in[4:0]);
                            end
                        end
                    end
                endcase
            end
            
            if (rom_wr && cpu_addr[7:0] == 8'h00 && !rom_wr_prev) begin
                // ROM select register
                rom_select_reg <= cpu_data_in;
                $display("ASIC: OUT on port df00, val=%02x", cpu_data_in);
                $display("ASIC: ROM select: %d", cpu_data_in);
            end
            
            if (ppi_wr && cpu_addr[7:0] == 8'h82 && !ppi_wr_prev) begin
                // PPI control register - just pass through to i8255 module
                ppi_control_reg <= cpu_data_in;
                $display("ASIC: OUT on port f782, val=%02x", cpu_data_in);
                $display("ASIC: PPI.control 0 => %d", cpu_data_in);
            end

            if (plus_wr && !plus_wr_prev && (cpu_data_in != last_plus_data)) begin
                // Plus control register - only process if data has changed
                $display("ASIC: OUT on port ef7f, val=%02x", cpu_data_in);
                $display("ASIC: Plus control: %02x", cpu_data_in);
                
                // TODO: Handle breakpoint rearming
                if (break_point == 32'hFFFFFFFF) begin
                    $display("ASIC: Rearming breakpoint");
                    break_point <= 0;  // Set breakpoint for next time
                end
            end

            // TODO: Handle FDC motor control
            if (fdc_wr && cpu_addr[7:0] == 8'h7E && !fdc_wr_prev && (cpu_data_in != last_fdc_data)) begin
                // FDC motor control - only process if data has changed
                $display("ASIC: OUT on port fa7e, val=%02x", cpu_data_in);
                $display("ASIC: FDC motor control access: %d - %d", cpu_addr[7:0], cpu_data_in);
            end

            if (f600_wr && !f600_wr_prev && (cpu_data_in != last_f600_data)) begin
                // F600 port write
                $display("ASIC: OUT on port f600, val=%02x", cpu_data_in);
                $display("ASIC: F600 port write: %d", cpu_data_in);
            end
        end
    end

    // Handle register reads
    always @(posedge clk_sys) begin
        cpu_data_out = 8'hFF;
        cpu_data_out_en = 0;
        asic_data_out = 8'hFF;  // Default ASIC data output
        asic_data_out_en = 0;   // Default ASIC data output enable

        if (reg_rd) begin
            case (cpu_addr[7:0])
                8'h00: begin cpu_data_out = ppi_port_a; cpu_data_out_en = 1; end
                8'h01: begin cpu_data_out = ppi_port_b; cpu_data_out_en = 1; end
                8'h02: begin cpu_data_out = ppi_port_c; cpu_data_out_en = 1; end
            endcase
        end
        else if (crtc_select_wr) begin
            asic_data_out = crtc_reg_select;
            asic_data_out_en = 1;
        end
        else if (crtc_data_wr) begin
            asic_data_out = crtc_regs_reg[crtc_reg_select];
            asic_data_out_en = 1;
        end
    end

    // Output assignments
    always @(posedge clk_sys) begin
        ram_config = ram_config_reg;
        rom_config = rom_config_reg;
        rom_select = rom_select_reg;
        ppi_control = ppi_control_reg;
        current_pen = current_pen_reg;
        pen_registers = asic_registers[current_pen_reg];
        mrer = mrer_reg;
    end

endmodule 