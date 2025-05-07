`timescale 1ns/1ps

module tb_gx4000_asic;

    // Testbench parameters
    localparam CLK_PERIOD = 10; // 100MHz clock

    // DUT signals
    logic         clk_sys;
    logic         reset;
    logic         gx4000_mode;
    logic         plus_mode;
    logic         force_unlock;
    
    // CPU interface
    logic [15:0]  cpu_addr;
    logic [7:0]   cpu_data_in;
    logic         cpu_wr;
    logic         cpu_rd;
    logic [7:0]   cpu_data_out;
    
    // Video interface
    logic [1:0]   r_in, g_in, b_in;
    logic [1:0]   r_out, g_out, b_out;
    logic         hblank, vblank;
    
    // Other connections set to default values for simplicity
    logic         palette_wr = 0;
    logic [3:0]   palette_addr = 0;
    logic [23:0]  palette_data = 0;
    logic         cart_download = 0;
    logic [24:0]  cart_addr = 0;
    logic [7:0]   cart_data = 0;
    logic         cart_wr = 0;
    
    // Protection status
    logic         asic_valid;
    logic [7:0]   asic_status;
    
    // Variables for testing
    int test_phase = 0;
    int passed_tests = 0;
    int failed_tests = 0;
    
    // Instantiate the DUT
    GX4000_ASIC dut (
        .clk_sys(clk_sys),
        .reset(reset),
        .gx4000_mode(gx4000_mode),
        .plus_mode(plus_mode),
        .force_unlock(force_unlock),
        
        // Video interface
        .r_in(r_in),
        .g_in(g_in),
        .b_in(b_in),
        .hblank(hblank),
        .vblank(vblank),
        .r_out(r_out),
        .g_out(g_out),
        .b_out(b_out),
        
        // CPU interface
        .cpu_addr(cpu_addr),
        .cpu_data_in(cpu_data_in),
        .cpu_wr(cpu_wr),
        .cpu_rd(cpu_rd),
        .cpu_data_out(cpu_data_out),
        
        // Palette interface
        .palette_wr(palette_wr),
        .palette_addr(palette_addr),
        .palette_data(palette_data),
        
        // Cartridge interface
        .cart_download(cart_download),
        .cart_addr(cart_addr),
        .cart_data(cart_data),
        .cart_wr(cart_wr),
        
        // Protection status
        .asic_valid(asic_valid),
        .asic_status(asic_status)
    );
    
    // Clock generation
    initial begin
        clk_sys = 0;
        forever #(CLK_PERIOD/2) clk_sys = ~clk_sys;
    end
    
    // File for waveform dump
    initial begin
        $dumpfile("build/tb_gx4000_asic.vcd");
        $dumpvars(0, tb_gx4000_asic);
    end
    
    // ASIC unlock sequence data
    // These 17 bytes form the complete unlock sequence
    const logic [7:0] UNLOCK_SEQUENCE [0:16] = 
    '{
        8'hFF, 8'h00, 8'hFF, 8'h77, 8'hB3, 8'h51, 8'hA8, 8'hD4,
        8'h62, 8'h39, 8'h9C, 8'h46, 8'h2B, 8'h15, 8'h8A, 8'hCD, 8'hEE
    };
    
    // CRTC register write task
    task crtc_write(input logic [7:0] reg_idx, input logic [7:0] data);
        cpu_addr = 16'hBC00;
        cpu_data_in = reg_idx;
        cpu_wr = 1;
        @(posedge clk_sys);
        @(posedge clk_sys);
        cpu_wr = 0;
        @(posedge clk_sys);
        @(posedge clk_sys);
        
        cpu_addr = 16'hBC01;
        cpu_data_in = data;
        cpu_wr = 1;
        @(posedge clk_sys);
        @(posedge clk_sys);
        cpu_wr = 0;
        @(posedge clk_sys);
        @(posedge clk_sys);
    endtask
    
    // Test the unlock sequence
    task test_unlock_sequence();
        $display("------------------------------------------------------");
        $display("STARTING UNLOCK SEQUENCE TEST");
        $display("------------------------------------------------------");
        
        // Set CRTC register to 0 (horizontal total)
        crtc_write(8'h00, 8'h00);
        
        for (int i = 0; i < 17; i++) begin
            $display("Sending unlock sequence byte %0d: 0x%h", i, UNLOCK_SEQUENCE[i]);
            crtc_write(8'h00, UNLOCK_SEQUENCE[i]);  // Always write to CRTC register 0
            
            // Add a small delay between writes to allow the ASIC to process
            repeat(5) @(posedge clk_sys);
        end
        
        // Check if the ASIC is now unlocked
        @(posedge clk_sys);
        @(posedge clk_sys);
        
        if (!dut.asic_locked) begin
            $display("SUCCESS: ASIC unlock sequence completed successfully!");
            passed_tests++;
        end else begin
            $display("FAILURE: ASIC is still locked after unlock sequence!");
            failed_tests++;
        end
        
        $display("------------------------------------------------------");
    endtask
    
    // Test force unlock
    task test_force_unlock();
        $display("------------------------------------------------------");
        $display("STARTING FORCE UNLOCK TEST");
        $display("------------------------------------------------------");
        
        reset = 1;
        force_unlock = 0;
        @(posedge clk_sys);
        @(posedge clk_sys);
        reset = 0;
        @(posedge clk_sys);
        @(posedge clk_sys);
        
        if (dut.asic_locked) begin
            $display("ASIC is locked as expected after reset");
            
            // Now use force_unlock
            force_unlock = 1;
            @(posedge clk_sys);
            @(posedge clk_sys);
            @(posedge clk_sys);
            
            if (!dut.asic_locked) begin
                $display("SUCCESS: Force unlock worked correctly!");
                passed_tests++;
            end else begin
                $display("FAILURE: ASIC is still locked after force_unlock!");
                failed_tests++;
            end
        end else begin
            $display("FAILURE: ASIC should be locked after reset!");
            failed_tests++;
        end
        
        force_unlock = 0;
        $display("------------------------------------------------------");
    endtask
    
    // Test setting ASIC state
    task test_asic_state();
        $display("------------------------------------------------------");
        $display("STARTING ASIC STATE TEST");
        $display("------------------------------------------------------");
        
        // First make sure the ASIC is unlocked
        force_unlock = 1;
        @(posedge clk_sys);
        @(posedge clk_sys);
        force_unlock = 0;
        @(posedge clk_sys);
        
        // Set key value and challenges
        cpu_addr = 16'h00E5;
        cpu_data_in = 8'h42;  // Arbitrary key value
        cpu_wr = 1;
        @(posedge clk_sys);
        @(posedge clk_sys);
        cpu_wr = 0;
        @(posedge clk_sys);
        
        // Set state to CHALLENGE
        cpu_addr = 16'h00E9;
        cpu_data_in = 8'h01;  // STATE_CHALLENGE
        cpu_wr = 1;
        @(posedge clk_sys);
        @(posedge clk_sys);
        cpu_wr = 0;
        @(posedge clk_sys);
        @(posedge clk_sys);
        
        // Check that asic_valid is now set
        if (asic_valid) begin
            $display("SUCCESS: ASIC valid flag set correctly after entering CHALLENGE state!");
            passed_tests++;
        end else begin
            $display("FAILURE: ASIC valid flag not set after entering CHALLENGE state!");
            failed_tests++;
        end
        
        // Try to read the status register
        cpu_addr = 16'h00EE;
        cpu_rd = 1;
        @(posedge clk_sys);
        @(posedge clk_sys);
        $display("Status register value: 0x%h", cpu_data_out);
        cpu_rd = 0;
        @(posedge clk_sys);
        
        $display("------------------------------------------------------");
    endtask
    
    // Main test sequence
    initial begin
        // Initialize signals
        reset = 1;
        gx4000_mode = 1;
        plus_mode = 0;
        force_unlock = 0;
        cpu_addr = 0;
        cpu_data_in = 0;
        cpu_wr = 0;
        cpu_rd = 0;
        r_in = 0;
        g_in = 0;
        b_in = 0;
        hblank = 0;
        vblank = 0;
        
        // Apply reset
        #100;
        reset = 0;
        #100;
        
        // Run tests
        test_unlock_sequence();
        test_force_unlock();
        test_asic_state();
        
        // Print test results
        $display("\n------------------------------------------------------");
        $display("TEST SUMMARY");
        $display("------------------------------------------------------");
        $display("Total tests: %0d", passed_tests + failed_tests);
        $display("Passed tests: %0d", passed_tests);
        $display("Failed tests: %0d", failed_tests);
        $display("------------------------------------------------------");
        
        // Finish simulation
        #1000;
        $display("Simulation completed");
        $finish;
    end

endmodule 