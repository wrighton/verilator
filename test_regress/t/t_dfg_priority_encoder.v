// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// 64-bit priority encoders, whose generated C++ used to take exponential time to compile
module t (
    input clk
);

  int cyc = 0;
  logic [63:0] crc = 64'h5aef0c8d_d70a4497;
  logic [63:0] req = '0;

  // Lowest set bit
  logic [5:0] lsb_idx;
  logic lsb_found;
  always_comb begin
    lsb_idx = 6'b0;
    lsb_found = 1'b0;
    for (int i = 0; i < 64; i++) begin
      if (req[i] && !lsb_found) begin
        lsb_idx = 6'(i);
        lsb_found = 1'b1;
      end
    end
  end

  // Highest set bit
  logic [5:0] msb_idx;
  logic msb_found;
  always_comb begin
    msb_idx = 6'b0;
    msb_found = 1'b0;
    for (int i = 63; i >= 0; i--) begin
      if (req[i] && !msb_found) begin
        msb_idx = 6'(i);
        msb_found = 1'b1;
      end
    end
  end

  // Lowest clear bit
  logic [5:0] zero_idx;
  logic zero_found;
  always_comb begin
    zero_idx = 6'b0;
    zero_found = 1'b0;
    for (int i = 0; i < 64; i++) begin
      if (!req[i] && !zero_found) begin
        zero_idx = 6'(i);
        zero_found = 1'b1;
      end
    end
  end

  always @(posedge clk) begin
    cyc <= cyc + 1;
    crc <= {crc[62:0], crc[63] ^ crc[2] ^ crc[0]};
    case (cyc)
      0: req <= '0;
      1: req <= '1;
      2: req <= 64'h80000000_00000000;
      3: req <= 64'h00000001_00000000;
      default: req <= cyc[0] ? crc << crc[63:58] : crc >> crc[63:58];
    endcase
    if (cyc > 0) begin
      `checkd(lsb_idx, req == '0 ? 6'd0 : 6'($clog2(req & -req)));
      `checkd(msb_idx, req == '0 ? 6'd0 : 6'($clog2({1'b0, req} + 65'd1) - 1));
      `checkd(zero_idx, req == '1 ? 6'd0 : 6'($clog2(~req & -(~req))));
    end
    if (cyc == 99) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

endmodule
