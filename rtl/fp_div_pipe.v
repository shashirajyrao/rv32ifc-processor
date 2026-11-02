
/*============================================================================

This Verilog source file is part of the Berkeley HardFloat IEEE Floating-Point
Arithmetic Package, Release 1, by John R. Hauser.

Copyright 2019 The Regents of the University of California.  All rights
reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
    this list of conditions, and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
    this list of conditions, and the following disclaimer in the documentation
    and/or other materials provided with the distribution.

 3. Neither the name of the University nor the names of its contributors may
    be used to endorse or promote products derived from this software without
    specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS "AS IS", AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, ARE
DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=============================================================================*/

`include "HardFloat_consts.vi"
// Local wrapper: pipelined rounding and registered divide/sqrt completion.
module
    fp_div_pipe#(
        parameter expWidth = 3, parameter sigWidth = 3, parameter options = 0
    ) (
        /*--------------------------------------------------------------------
        *--------------------------------------------------------------------*/
        input nReset,
        input clock,
        /*--------------------------------------------------------------------
        *--------------------------------------------------------------------*/
        input [(`floatControlWidth - 1):0] control,
        /*--------------------------------------------------------------------
        *--------------------------------------------------------------------*/
        output inReady,
        input inValid,
        input sqrtOp,
        input [(expWidth + sigWidth):0] a,
        input [(expWidth + sigWidth):0] b,
        input [2:0] roundingMode,
        /*--------------------------------------------------------------------
        *--------------------------------------------------------------------*/
        output outValid,
        output sqrtOpOut,
        output [(expWidth + sigWidth):0] out,
        output [4:0] exceptionFlags
    );

    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    // sqrtOpOut is already declared as an output net above (Vivado compatibility).
    wire rawValid;
    reg v1,v2;
    wire [expWidth+sigWidth:0] rounded;
    wire [4:0] roundedFlags;
    reg [expWidth+sigWidth:0] out_q;
    reg [4:0] flags_q;
    assign out=out_q; assign exceptionFlags=flags_q; assign outValid=v2;
    always @(posedge clock) begin
     if(!nReset) begin v1<=0;v2<=0;end
     else begin v1<=rawValid;v2<=v1;end
     out_q<=rounded;flags_q<=roundedFlags;
    end
    wire [2:0] roundingModeOut;
    wire invalidExc, infiniteExc, out_isNaN, out_isInf, out_isZero, out_sign;
    wire signed [(expWidth + 1):0] out_sExp;
    wire [(sigWidth + 2):0] out_sig;
    divSqrtRecFNToRaw_small#(expWidth, sigWidth, options)
        divSqrtRecFNToRaw(
            nReset,
            clock,
            control,
            inReady,
            inValid,
            sqrtOp,
            a,
            b,
            roundingMode,
            rawValid,
            sqrtOpOut,
            roundingModeOut,
            invalidExc,
            infiniteExc,
            out_isNaN,
            out_isInf,
            out_isZero,
            out_sign,
            out_sExp,
            out_sig
        );
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    fp_round_pipe#(expWidth, sigWidth+2, expWidth, sigWidth, 0)
        roundRawOut(
            clock,
            control,
            invalidExc,
            infiniteExc,
            out_isNaN,
            out_isInf,
            out_isZero,
            out_sign,
            out_sExp,
            out_sig,
            roundingModeOut,
            rounded,
            roundedFlags
        );

endmodule



