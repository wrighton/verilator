// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

module sub;
  initial begin : \outer-b
    begin : \blk-d
    end
  end
endmodule

module t;
  sub \u-x ();
  sub TOP ();

  initial begin : \blk-a
    disable \blk-a ;
  end

  initial begin : \fork
    disable \fork ;
  end

  initial begin : \outer-a
    begin : \blk-e
    end
  end

  // A target found in an enclosing scope, with a block of the same name as one around it nearer
  initial begin : \outer-s
    begin : \worker-s
      begin : \outer-s
        disable \worker-s ;
      end
    end
  end

  task \tsk-c ;
  endtask

  initial begin
    disable \tsk-c ;
    disable \outer-a .\blk-e ;
    disable \u-x .\outer-b .\blk-d ;
    disable TOP.\outer-b ;  // An instance named like the top, with a local block of the same name
  end

  initial begin : \outer-b
  end
endmodule
