// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t;

  typedef int aa_t[string];

  task automatic t_inout(inout int io[string]);
    fork
      begin
        #1;
        io["a"] = 2;  // Unsupported: associative inout written by a surviving fork
      end
    join_none
  endtask

  task automatic t_output(output byte o[int]);
    fork
      begin
        #1;
        o[3] = 4;  // Unsupported: associative output written by a surviving fork
      end
    join_none
  endtask

  task automatic t_typedef(inout aa_t io_td);
    fork
      begin
        #1;
        io_td["b"] = 3;  // Unsupported: typedef'd associative inout written by a surviving fork
      end
    join_none
  endtask

  function automatic aa_t f_ret();
    fork
      begin
        #1;
        f_ret["c"] = 5;  // Unsupported: associative return variable written by a surviving fork
      end
    join_none
  endfunction

endmodule
