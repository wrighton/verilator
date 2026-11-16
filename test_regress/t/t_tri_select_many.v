// DESCRIPTION: Verilator: Tristate net with many part select drivers
//
// This file ONLY is placed under the Creative Commons Public Domain
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);
  int cyc = 0;
  logic [64:0] crc = 65'h1_5aef_0c8d_d70a_4497;
  logic [64:0] d;
  logic [64:0] en;
  logic sel;
  always_comb begin
    d = crc;
    en = {crc[0], crc[64:1]} ^ crc;
    sel = crc[3];
  end

  // One driver per bit
  tri0 [64:0] bits;
  for (genvar i = 0; i < 65; ++i) begin : gen_bits
    assign bits[i] = en[i] ? d[i] : 1'bz;
  end

  // Drivers of overlapping selects
  wire [32:0] fields;
  for (genvar i = 0; i < 33; ++i) begin : gen_fields_bit
    assign fields[i] = sel ? d[i] : 1'bz;
  end
  for (genvar i = 0; i < 11; ++i) begin : gen_fields_field
    assign fields[i*3+:3] = sel ? 3'bz : ~d[i*3+:3];
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[63:0], crc[64] ^ crc[2] ^ crc[0]};
    `checkh(bits, d & en);
    `checkh(fields, sel ? d[32:0] : ~d[32:0]);
    if (cyc == 20) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end
endmodule
