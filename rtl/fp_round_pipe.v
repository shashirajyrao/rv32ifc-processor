
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
`include "HardFloat_specialize.vi"

// Modified locally: internal rounding pipeline; used with (8,26,8,24,0).
module
    fp_round_pipe#(
        parameter inExpWidth = 3,
        parameter inSigWidth = 3,
        parameter outExpWidth = 3,
        parameter outSigWidth = 3,
        parameter options = 0
    ) (
        input clk,
        input [(`floatControlWidth - 1):0] control,
        input invalidExc,     // overrides 'infiniteExc' and 'in_*' inputs
        input infiniteExc,    // overrides 'in_*' inputs except 'in_sign'
        input in_isNaN,
        input in_isInf,
        input in_isZero,
        input in_sign,
        input signed [(inExpWidth + 1):0] in_sExp,   // limited range allowed
        input [inSigWidth:0] in_sig,
        input [2:0] roundingMode,
        output [(outExpWidth + outSigWidth):0] out,
        output [4:0] exceptionFlags
    );

    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    localparam sigMSBitAlwaysZero =
        ((options & `flRoundOpt_sigMSBitAlwaysZero) != 0);
    localparam effectiveInSigWidth =
        sigMSBitAlwaysZero ? inSigWidth : inSigWidth + 1;
    localparam neverUnderflows =
        ((options
              & (`flRoundOpt_neverUnderflows
                     | `flRoundOpt_subnormsAlwaysExact))
             != 0)
            || (inExpWidth < outExpWidth);
    localparam neverOverflows =
        ((options & `flRoundOpt_neverOverflows) != 0)
            || (inExpWidth < outExpWidth);
    localparam adjustedExpWidth =
          (inExpWidth < outExpWidth) ? outExpWidth + 1
        : (inExpWidth == outExpWidth) ? inExpWidth + 2
        : inExpWidth + 3;
    localparam outNaNExp = 7<<(outExpWidth - 2);
    localparam outInfExp = 6<<(outExpWidth - 2);
    localparam outMaxFiniteExp = outInfExp - 1;
    localparam outMinNormExp = (1<<(outExpWidth - 1)) + 2;
    localparam outMinNonzeroExp = outMinNormExp - outSigWidth + 1;
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire roundingMode_near_even   = (roundingMode == `round_near_even);
    wire roundingMode_minMag      = (roundingMode == `round_minMag);
    wire roundingMode_min         = (roundingMode == `round_min);
    wire roundingMode_max         = (roundingMode == `round_max);
    wire roundingMode_near_maxMag = (roundingMode == `round_near_maxMag);
    wire roundingMode_odd         = (roundingMode == `round_odd);
    wire roundMagUp =
        (roundingMode_min && in_sign) || (roundingMode_max && !in_sign);
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire isNaNOut = invalidExc || (!infiniteExc && in_isNaN);
`ifdef HardFloat_propagateNaNPayloads
    wire propagateNaNPayload = isNaNOut;
`else
    wire propagateNaNPayload = 0;
`endif
    wire signed [(adjustedExpWidth - 1):0] sAdjustedExp =
        in_sExp + ((1<<outExpWidth) - (1<<inExpWidth));
    wire [(outSigWidth + 2):0] adjustedSig;
    generate
        if (inSigWidth <= outSigWidth + 2) begin
            assign adjustedSig = in_sig<<(outSigWidth - inSigWidth + 2);
        end else begin
            assign adjustedSig =
                {in_sig[inSigWidth:(inSigWidth - outSigWidth - 1)],
                 |in_sig[(inSigWidth - outSigWidth - 2):0]};
        end
    endgenerate
    wire doShiftSigDown1 =
        sigMSBitAlwaysZero ? 0 : adjustedSig[outSigWidth + 2];
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    // Pipeline boundary: rounded significand and matching control metadata.
    reg signed [adjustedExpWidth-1:0] sAdjustedExp_q;
    reg  doShiftSigDown1_q;
    reg [outSigWidth+2:0] adjustedSig_q;
    reg [`floatControlWidth-1:0] control_q;
    reg  roundingMode_near_even_q;
    reg  roundingMode_near_maxMag_q;
    reg  roundingMode_odd_q;
    reg  roundMagUp_q;
    reg  isNaNOut_q;
    reg  infiniteExc_q;
    reg  in_isInf_q;
    reg  in_isZero_q;
    reg  in_sign_q;
    reg  invalidExc_q;
    always @(posedge clk) begin
        sAdjustedExp_q<=sAdjustedExp;
        doShiftSigDown1_q<=doShiftSigDown1;
        adjustedSig_q<=adjustedSig;
        control_q<=control;
        roundingMode_near_even_q<=roundingMode_near_even;
        roundingMode_near_maxMag_q<=roundingMode_near_maxMag;
        roundingMode_odd_q<=roundingMode_odd;
        roundMagUp_q<=roundMagUp;
        isNaNOut_q<=isNaNOut;
        infiniteExc_q<=infiniteExc;
        in_isInf_q<=in_isInf;
        in_isZero_q<=in_isZero;
        in_sign_q<=in_sign;
        invalidExc_q<=invalidExc;
    end
    wire [outExpWidth:0] common_expOut;
    wire [(outSigWidth - 2):0] common_fractOut;
    wire common_overflow, common_totalUnderflow, common_underflow;
    wire common_inexact;
    generate
        if (
            neverOverflows && neverUnderflows
                && (effectiveInSigWidth <= outSigWidth)
        ) begin
            /*----------------------------------------------------------------
            *----------------------------------------------------------------*/
            assign common_expOut = sAdjustedExp + doShiftSigDown1;
            assign common_fractOut =
                doShiftSigDown1 ? adjustedSig>>3 : adjustedSig>>2;
            assign common_overflow       = 0;
            assign common_totalUnderflow = 0;
            assign common_underflow      = 0;
            assign common_inexact        = 0;
        end else begin
            /*----------------------------------------------------------------
            *----------------------------------------------------------------*/
            wire [(outSigWidth + 2):0] roundMask;
            if (neverUnderflows) begin
                assign roundMask = {doShiftSigDown1, 2'b11};
            end else begin
                wire [outSigWidth:0] roundMask_main;
                lowMaskLoHi#(
                    outExpWidth + 1,
                    outMinNormExp - outSigWidth - 1,
                    outMinNormExp
                ) lowMask_roundMask(
                        sAdjustedExp[outExpWidth:0]
                            | (propagateNaNPayload ? 1'b1<<outExpWidth : 1'b0),
                        roundMask_main
                    );
                assign roundMask = {roundMask_main | doShiftSigDown1, 2'b11};
            end
            wire [(outSigWidth + 2):0] shiftedRoundMask = roundMask>>1;
            wire [(outSigWidth + 2):0] roundPosMask =
                ~shiftedRoundMask & roundMask;
            wire roundPosBit =
                (|(adjustedSig[(outSigWidth + 2):3]
                       & roundPosMask[(outSigWidth + 2):3]))
                    || ((|(adjustedSig[2:0] & roundPosMask[2:0]))
                            && !propagateNaNPayload);
            wire anyRoundExtra =
                (|(adjustedSig[(outSigWidth + 2):3]
                       & shiftedRoundMask[(outSigWidth + 2):3]))
                    || ((|(adjustedSig[2:0] & shiftedRoundMask[2:0]))
                            && !propagateNaNPayload);
            wire anyRound = roundPosBit || anyRoundExtra;
            /*----------------------------------------------------------------
            *----------------------------------------------------------------*/
            wire roundIncr =
                ((roundingMode_near_even || roundingMode_near_maxMag)
                     && roundPosBit)
                    || (roundMagUp && anyRound);
            wire [(outSigWidth + 1):0] roundedSig_pre =
                roundIncr
                    ? (((adjustedSig | roundMask)>>2) + 1)
                          & ~(roundingMode_near_even && roundPosBit
                                  && !anyRoundExtra
                                  ? roundMask>>1 : 0)
                    : (adjustedSig & ~roundMask)>>2
                          | (roundingMode_odd && anyRound
                                 ? roundPosMask>>1 : 0);
            reg [outSigWidth+1:0] roundedSig;
            reg [outSigWidth+2:0] roundMask_q;
            reg  roundPosBit_q;
            reg  anyRound_q;
            always @(posedge clk) begin
                roundedSig<=roundedSig_pre;
                roundMask_q<=roundMask;
                roundPosBit_q<=roundPosBit;
                anyRound_q<=anyRound;
            end
            wire signed [adjustedExpWidth:0] sExtAdjustedExp = sAdjustedExp_q;
            wire signed [adjustedExpWidth:0] sRoundedExp =
                sExtAdjustedExp + (roundedSig>>outSigWidth);
            /*----------------------------------------------------------------
            *----------------------------------------------------------------*/
            assign common_expOut = sRoundedExp;
            assign common_fractOut =
                doShiftSigDown1_q ? roundedSig>>1 : roundedSig;
            assign common_overflow =
                neverOverflows ? 0 : (sRoundedExp>>>(outExpWidth - 1) >= 3);
            assign common_totalUnderflow =
                neverUnderflows ? 0 : (sRoundedExp < outMinNonzeroExp);
            /*----------------------------------------------------------------
            *----------------------------------------------------------------*/
            wire unboundedRange_roundPosBit =
                doShiftSigDown1_q ? adjustedSig_q[2] : adjustedSig_q[1];
            wire unboundedRange_anyRound =
                (doShiftSigDown1_q && adjustedSig_q[2]) || (|adjustedSig_q[1:0]);
            wire unboundedRange_roundIncr =
                ((roundingMode_near_even_q || roundingMode_near_maxMag_q)
                     && unboundedRange_roundPosBit)
                    || (roundMagUp_q && unboundedRange_anyRound);
            wire roundCarry =
                doShiftSigDown1_q
                    ? roundedSig[outSigWidth + 1] : roundedSig[outSigWidth];
            assign common_underflow =
                neverUnderflows ? 0
                    : common_totalUnderflow
                          || (anyRound_q && (sAdjustedExp_q>>>outExpWidth <= 0)
                                  && (doShiftSigDown1_q
                                          ? roundMask_q[3] : roundMask_q[2])
                                  && !(((control_q
                                           & `flControl_tininessAfterRounding)
                                            != 0)
                                           && !(doShiftSigDown1_q ? roundMask_q[4]
                                                    : roundMask_q[3])
                                           && roundCarry && roundPosBit_q
                                           && unboundedRange_roundIncr));
            /*----------------------------------------------------------------
            *----------------------------------------------------------------*/
            assign common_inexact = common_totalUnderflow || anyRound_q;
        end
    endgenerate
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire notNaN_isSpecialInfOut = infiniteExc_q || in_isInf_q;
    wire commonCase = !isNaNOut_q && !notNaN_isSpecialInfOut && !in_isZero_q;
    wire overflow  = commonCase && common_overflow;
    wire underflow = commonCase && common_underflow;
    wire inexact = overflow || (commonCase && common_inexact);
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
    wire overflow_roundMagUp =
        roundingMode_near_even_q || roundingMode_near_maxMag_q || roundMagUp_q;
    wire pegMinNonzeroMagOut =
        commonCase && common_totalUnderflow
            && (roundMagUp_q || roundingMode_odd_q);
    wire pegMaxFiniteMagOut = overflow && !overflow_roundMagUp;
    wire notNaN_isInfOut =
        notNaN_isSpecialInfOut || (overflow && overflow_roundMagUp);
    /*------------------------------------------------------------------------
    *------------------------------------------------------------------------*/
`ifdef HardFloat_propagateNaNPayloads
    wire signOut = in_sign_q;
`else
    wire signOut = isNaNOut_q ? `HardFloat_signDefaultNaN : in_sign_q;
`endif
    wire [outExpWidth:0] expOut =
        (common_expOut
             & ~(in_isZero_q || common_totalUnderflow ? 7<<(outExpWidth - 2) : 0)
             & ~(pegMinNonzeroMagOut               ? ~outMinNonzeroExp    : 0)
             & ~(pegMaxFiniteMagOut                ? 1<<(outExpWidth - 1) : 0)
             & ~(notNaN_isInfOut                   ? 1<<(outExpWidth - 2) : 0))
            | (pegMinNonzeroMagOut ? outMinNonzeroExp : 0)
            | (pegMaxFiniteMagOut  ? outMaxFiniteExp  : 0)
            | (notNaN_isInfOut     ? outInfExp        : 0)
            | (isNaNOut_q            ? outNaNExp        : 0);
`ifdef HardFloat_propagateNaNPayloads
    wire [(outSigWidth - 2):0] fractOut =
        {isNaNOut_q
             || (!in_isZero_q && !common_totalUnderflow
                     && common_fractOut[outSigWidth - 2]),
         isNaNOut_q || (!in_isZero_q && !common_totalUnderflow)
             ? common_fractOut[(outSigWidth - 3):0] : 1'b0}
            | {(outSigWidth - 1){pegMaxFiniteMagOut}};
`else
    wire [(outSigWidth - 2):0] fractOut =
          (isNaNOut_q ? `HardFloat_fractDefaultNaN(outSigWidth) : 0)
        | (!in_isZero_q && !common_totalUnderflow
               ? common_fractOut & `HardFloat_fractDefaultNaN(outSigWidth) : 0)
        | (!isNaNOut_q && !in_isZero_q && !common_totalUnderflow
               ? common_fractOut & ~`HardFloat_fractDefaultNaN(outSigWidth)
               : 0)
        | {(outSigWidth - 1){pegMaxFiniteMagOut}};
`endif
    assign out = {signOut, expOut, fractOut};
    assign exceptionFlags =
        {invalidExc_q, infiniteExc_q, overflow, underflow, inexact};

endmodule
