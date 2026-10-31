// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2023 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// bug3806

// verilog_format: off
`define stop $stop
`define checkh(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0x exp=%0x (%s !== %s)\n", `__FILE__,`__LINE__, (gotv), (expv), `"gotv`", `"expv`"); `stop; end while(0);
// verilog_format: on

module t (
    input clk
);

  reg [65:0] idx  /*verilator public_flat_rw*/;
  initial idx = 1;

  wire unlikely = idx > 200;

  typedef enum logic {
    UP,
    DOWN
  } dir_t;

  dir_t direction;

  always_comb direction = idx % 2 == 0 ? UP : DOWN;

  int ups;  // Make computable

  // An if/else chain repeating its condition takes its first branch
  wire chain_sel = idx[1];
  logic chain;
  always_comb begin
    if (chain_sel) chain = idx[2];
    else if (chain_sel) chain = idx[3];
    else if (chain_sel) chain = idx[4];
    else if (chain_sel) chain = idx[5];
    else chain = 1'b0;
  end

  // A condition repeated in its then branch takes the then branch
  logic nested;
  always_comb nested = chain_sel ? (chain_sel ? idx[2] : idx[3]) : idx[4];

  always @(posedge clk) begin
    `checkh(chain, idx[1] & idx[2]);
    `checkh(nested, idx[1] ? idx[2] : idx[4]);
    if (idx > 100) begin
`ifdef TEST_VERBOSE
      $write("ups = %0d\n", ups);
`endif
      if (ups != 50049) $stop;
      $write("*-* All Finished *-*\n");
      $finish;
    end

    if (direction == UP) ++ups;
    else if (direction == UP) ++ups;
    else ups += 1000;

    case (direction)
      DOWN: idx = idx + 3;
      UP: idx = idx - 1;
      default: begin
        // This if just gets rid of branch pred on default^
        if (unlikely == '1) begin
          $write("never\n");
        end
      end
    endcase
  end

endmodule
