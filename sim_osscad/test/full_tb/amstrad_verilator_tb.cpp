#include <verilated.h>
#include <verilated_vcd_c.h>
#include "VAmstrad.h"

#include <iostream>
#include <string>

// Simulation time
vluint64_t main_time = 0;

// Called by $time in Verilog
double sc_time_stamp() {
    return main_time;
}

int main(int argc, char** argv) {
    // Initialize Verilator
    Verilated::commandArgs(argc, argv);
    
    // Create VCD file
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    
    // Create an instance of our module
    VAmstrad* top = new VAmstrad;
    top->trace(tfp, 99);
    tfp->open("amstrad_trace.vcd");
    
    // Initialize inputs
    top->CLK_50M = 0;
    top->RESET = 1;  // Start with reset active
    
    // Initial setup for HPS status
    // Bit 21 is used to indicate GX4000 mode
    top->HPS_BUS = 0;  // Would need proper simulation of HPS_BUS
    
    // Run simulation for a set number of clock cycles
    for (int i = 0; i < 10000; i++) {
        // Toggle clock
        top->CLK_50M = !top->CLK_50M;
        
        // Release reset after a few clock cycles
        if (i > 10) {
            top->RESET = 0;
        }
        
        // Evaluate the model
        top->eval();
        tfp->dump(main_time);
        main_time++;
        
        // Print some output occasionally
        if (i % 100 == 0) {
            std::cout << "Time: " << main_time 
                      << ", HSync: " << (top->VGA_HS ? 1 : 0)
                      << ", VSync: " << (top->VGA_VS ? 1 : 0)
                      << ", Active: " << (top->VGA_DE ? 1 : 0)
                      << std::endl;
        }
    }
    
    // Clean up
    tfp->close();
    delete tfp;
    delete top;
    
    return 0;
} 