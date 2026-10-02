//=============================================================================
// Module: full_adder
// Description: 1-bit Full Adder — fundamental building block of the ALU
//              Gate-level implementation matching 8085 architecture docs.
//
// Equations:
//   Sum  = A ^ B ^ Cin
//   Cout = (A & B) | (Cin & (A ^ B))
//=============================================================================

module full_adder (
    input  wire a,      // Operand A bit
    input  wire b,      // Operand B bit
    input  wire cin,    // Carry-in
    output wire sum,    // Sum output
    output wire cout    // Carry-out
);

    // Internal signals
    wire a_xor_b;       // Propagate signal: P = A ^ B
    wire a_and_b;       // Generate signal:  G = A & B
    wire cin_and_p;     // Cin & P

    // Gate-level implementation
    assign a_xor_b  = a ^ b;              // XOR gate 1: Propagate
    assign sum      = a_xor_b ^ cin;      // XOR gate 2: Sum
    assign a_and_b  = a & b;              // AND gate 1: Generate
    assign cin_and_p = cin & a_xor_b;     // AND gate 2: Carry propagate
    assign cout     = a_and_b | cin_and_p; // OR gate:   Carry-out

endmodule
