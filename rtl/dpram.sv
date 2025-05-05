//
// dpram.sv
//
// sdram controller implementation for the MiSTer board by
//
// Copyright (c) 2020 Frank Bruno
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

module dpram #(
    parameter data_width_g = 8,
    parameter addr_width_g = 14
) (
    input   wire                        clock_a,
    input   wire                        clock_b,
    // Port A
    input   wire                        ram_cs,    
    input   wire                        wren_a,
    input   wire    [addr_width_g-1:0]  address_a,
    input   wire    [data_width_g-1:0]  data_a,
    output  reg   [data_width_g-1:0]  q_a,

    // Port B
    input   wire                        ram_cs_b,    
    input   wire                        wren_b,
    input   wire    [addr_width_g-1:0]  address_b,
    input   wire    [data_width_g-1:0]  data_b,
    output  logic   [data_width_g-1:0]  q_b
);

// Shared memory
logic [data_width_g-1:0] mem [(2**addr_width_g)-1:0];

// Port A
always @(posedge clock_a) begin
	q_a <= mem[address_a];
    if(wren_a) begin
        mem[address_a] <= data_a;
    end
end

// Port B
always @(posedge clock_b) begin
	q_b <= mem[address_b];         
    if(wren_b) begin
        mem[address_b] <= data_b;
    end
end

endmodule
