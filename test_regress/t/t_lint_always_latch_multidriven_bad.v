// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module t (
    input e,
    input d,
    output logic out1,
    output logic out2,
    output logic out3,
    output logic out4,
    output logic out5,
    output logic out6
);

  always_latch if (e) out1 = d;
  always_latch if (!e) out1 = d;  // <--- Warning

  always_latch if (e) out2 = d;
  assign out2 = d;  // <--- Warning

  assign out3 = d;
  always_latch if (e) out3 = d;  // <--- Warning

  always_comb out4 = d;
  always_latch if (e) out4 = d;  // <--- Warning

  task automatic set_out5();
    out5 = d;
  endtask
  always_latch begin
    if (e) begin
      out5 = 1'b0;
      set_out5();
    end
  end
  always_latch if (!e) out5 = d;  // <--- Warning

  // Legal
  always_latch begin
    if (e) out6 = d;
    if (!e) out6 = d;
  end

endmodule
