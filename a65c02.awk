#!/usr/bin/awk -f
# vim600: set foldmethod=marker: # Faster folding in VIM.
#
# 65c02 Assembler. {{{1
#
# Assembles 65c02 source into plain text object files.
#
# Copyright (C) 2007 Lorance Stinson All rights reserved.  This script is free
# software.  It may be copied or modified according to the same terms as Perl.
#
# For more information email <LoranceStinson+65c02@gmail.com>.
# Or see http://lorance.freeshell.org/

# Documentation: {{{1
#
# Global Variables:
# Assembly:
# inst_count=0      - The number of instructions loaded.
#                     Used to index src_code.
# src_code=[]       - The instructions loaded from the source.
#                     Keyed by sequential number.
#                     The array has several parts:
#                         num,1 = First operand byte.
#                         num,2 = Second operand byte.
#                         num,A = Address.
#                         num,B = Bytes in addition to the instruction.
#                         num,C = OP code.
#                         num,D = Dependency.
#                                 Only set if a symbol was undefined.
#                         num,F = Original source file.
#                         num,L = Listing option. See list_array below.
#                         num,N = Original source file line #.
#                         num,M = Macro name.
#                         num,O = Original source code.
#                         num,R = Uses a relative address. (1 / 0)
# pgm_cntr          - The current PC.
# data_loc=[]       - The data locations array. Address -> Size
# symbols=[]        - The symbol table. Symbol -> Value
# sym_count=[]      - The number of times a symbol is refrenced. Symbol -> Count
# last_label=""     - The last label encountered. Used for local labels.
# list_array=[]     - Contains options for assembly and listing.
#                     The options are:
#                       list = Controls source listing.
#                             -1 = List only compiled source.
#                              0 = Do not list any source.
#                              1 = List all source.
#                       data = List data locations. 1 = enabled, 0 = disabled.
#                       sym  = List symbol table. 1 = enabled, 0 = disabled.
# errors=[]         - Errors encountered during assembly. Number -> Text
#                     _count contains the error counter.
# macros=[]         - Holds macros. Keyed by the macro name and points to the
#                     location in src_code where the macro starts.
#                     The array also has meta information about the macros:
#                     _name = The name of the macro currently being loaded.
#                             Instead of being assembled the source is saved to
#                             macros using this name.
#                     _call = The number of macro calls made.
#                             Incremented before each call.
#
# The file being loaded:
# file_name=""      - The current file name.
# file_line=""      - The current file line.
#
# Internal:
# convert_str       - Used for converting between bases.
# ascii_str         - Used for converting between numbers and characters.
# inst_encode       - Used for encoding instructions.
#
# Addressing modes:
# The number is the index into the encoding string for the OP code.
#+---------------------+-----+----------+
#| Mode                | Num | Format   |
#+=====================+=====+==========+
#| Immediate           |*0   | #aa      |
#| Absolute            |*1   | aaaa     |
#| Zero Page           |*2   | aa       |
#| Indirect Zero Page  |*3   | (aa)     |
#| Implied             |*4   |          |
#| Indirect Absolute   |*5   | (aaaa)   |
#| Abs Indexed Inder,X |*6   | (aaaa,X) |
#| Absolute Indexed,X  |*7   | aaaa,X   |
#| Absolute Indexed,Y  |*8   | aaaa,Y   |
#| Zero Page Indexed,X |*9   | aa,X     |
#| Zero Page Indexed,Y |*10  | aa,Y     |
#| Indexed Indirect    |*11  | (aa,X)   |
#| Indirect Indexed    |*12  | (aa),Y   |
#| Accumulator         |*13  | A        |
#+---------------------+-----+----------+

# AWK BEGIN/END/line. {{{1

# Initialization. {{{2
BEGIN {
    # Used for converting the base of a number,
    convert_str = "0123456789ABCDEF"

    # Used for converting between numbers and characters.
    ascii_str = " !\"#$%&'()*+,-./0123456789:;<=>?@" \
                "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`" \
                "abcdefghijklmnopqrstuvwxyz{|}~ "

    # Instructions and their addressing modes.
    inst_encode =   "#ADC696D6572      7D7975  6171  " \
                    "#AND292D2532      3D3935  2131  " \
                    "#ASL0A0E06  0A    1E  16      0A" \
                    "#BCC    90                      " \
                    "#BCS    B0                      " \
                    "#BEQ    F0                      " \
                    "#BIT892C24        3C  34        " \
                    "#BMI    30                      " \
                    "#BNE    D0                      " \
                    "#BPL    10                      " \
                    "#BRA    80                      " \
                    "#BRK        00                  " \
                    "#BVC    50                      " \
                    "#BVS    70                      " \
                    "#CLC        18                  " \
                    "#CLD        D8                  " \
                    "#CLI        58                  " \
                    "#CLV        B8                  " \
                    "#CMPC9CDC5D2      DDD9D5  C1D1  " \
                    "#CPXE0ECE4                      " \
                    "#CPYC0CCC4                      " \
                    "#DEA        3A                  " \
                    "#DEC  CEC6        DE  D6        " \
                    "#DEX        CA                  " \
                    "#DEY        88                  " \
                    "#EOR494D4552      5D5955  4151  " \
                    "#INA        1A                  " \
                    "#INC  EEE6        FE  F6        " \
                    "#INX        E8                  " \
                    "#INY        C8                  " \
                    "#JMP  4C      6C7C              " \
                    "#JSR  20                        " \
                    "#LDAA9ADA5B2      BDB9B5  A1B1  " \
                    "#LDXA2AEA6          BE  B6      " \
                    "#LDYA0ACA4        BC  B4        " \
                    "#LSR4A4E46  4A    5E  56      4A" \
                    "#NOP        EA                  " \
                    "#ORA090D0512      1D1915  0111  " \
                    "#PHA        48                  " \
                    "#PHP        08                  " \
                    "#PHX        DA                  " \
                    "#PHY        5A                  " \
                    "#PLA        68                  " \
                    "#PLP        28                  " \
                    "#PLX        FA                  " \
                    "#PLY        7A                  " \
                    "#ROL2A2E26  2A    3E  36      2A" \
                    "#ROR6A6E66  6A    7E  76      6A" \
                    "#RTI        40                  " \
                    "#RTS        60                  " \
                    "#SBCE9EDE5F2      FDF9F5  E1F1  " \
                    "#SEC        38                  " \
                    "#SED        F8                  " \
                    "#SEI        78                  " \
                    "#STA  8D8592      9D9995  8191  " \
                    "#STX  8E86              96      " \
                    "#STY  8C84            94        " \
                    "#STZ  9C64        9E  74        " \
                    "#TAX        AA                  " \
                    "#TAY        A8                  " \
                    "#TRB  1C14                      " \
                    "#TSB  0C04                      " \
                    "#TSX        BA                  " \
                    "#TXA        8A                  " \
                    "#TXS        9A                  " \
                    "#TYA        98                  "

    # No errors encountered yet.
    errors["_count"] = 0

    # No source read yet.
    inst_count = 0

    # Start the Program Counter at 0.
    pgm_cntr = 0

    # Set the default source listing options.
    list_array["list"] = 1
    list_array["data"] = 1
    list_array["sym"] = 1

    # No macro being loaded yet.
    macros["_name"] = ""
    macros["_call"] = 0

    # Default last_label value.
    last_label = "BLANK"
}

# Print the errors, symbols and assembled source. {{{2
END {
    # Run the second pass to make sure everything is finished.
    second_pass()

    # See if there were any errors.
    if (errors["_count"] != 0) {
        # Print the errors.
        print "; ***** There were errors during assembly!"
        print_errors()
        print ""
    }

    # Print the data locations.
    if (list_array["data"] == 1) {
        print_data()
        print ""
    }

    # Print the symbol table.
    if (list_array["sym"] == 1) {
        print_symbols()
        print ""
    }

    # Print the assembled source.
    print_assembled()

    # Exit with error status if there were errors.
    if (errors["_count"] != 0) {
        exit 1
    }
}

# Load source files passed on the command line or via STDIN. {{{2
{
    # Set the file name and line.
    file_name = FILENAME
    file_line = FNR

    # Load the line.
    load_source($0)
}

# Assembly functions: {{{1

# encode_branch(low, high, base, target) - Encodes a branch address. {{{2
# low       - The low byte of the address.
# high      - The high byte of the address.
# base      - The base address of the branch.
# branch    - The branch value. (Private)
function encode_branch(low, high, base, branch) {
    # Get the branch.
    branch = word_make(low, high) - base - 1

    # Make sure the branch is not too large.
    if (branch > 127 || branch < -128) {
        add_error(sprintf("Branch too large (%d)", branch))
        return ""
    }

    # Adjust the branch if it's negative.
    if (branch < 0) {
        branch = branch + 256
    }

    # Return the branch.
    return branch
}

# encode_instr(inst, oper) - Attempt to encode the instruction. {{{2
# inst      - The instruction.
# oper      - The operand.
# code      - The OP code/line in the encoding string. (Private)
# mode      - The addressing mode. (Private)
# bytes     - Bytes used in addition to the instruction. (Private)
function encode_instr(inst, oper, code, mode, bytes) {
    # Search for the OP code in the encoding table.
    code = index(inst_encode, "#" inst)
    if  (length(inst) != 3 || code == 0) {
        # See if it's a Sweet 16 instruction.
        encode_sweet16(inst, oper)
        return
    }
    code = code + 4

    # Default to 0 bytes.
    bytes = 0

    # Attempt to determine the addressing mode.
    # See the section "Addressing modes" in the documentation above.
    if (oper == "") {
        # Implied.
        mode = 4
    } else if (oper == "A") {
        # Accumulator.
        mode = 13
    } else if (substr(oper, 1, 1) == "#") {
        # Immediate.
        mode = 0
        bytes = 1

        # Get the value of the operand.
        if (eval_operand(substr(oper, 2, length(oper) - 1), inst_count, 0) == 2) {
            add_error("Operand larger than a byte")
        }
    } else if (inst ~ /^B[^I].$/) {
        # Branch. (Stored in the zero page column.)
        mode = 2
        bytes = 1

        # Mark it as using a relative address. This is so the address is
        # adjusted correctly if a symbol is not defined now.
        src_code[inst_count, "R"] = 1

        # Get the value of the operand.
        oper = eval_operand(oper, inst_count, 0)
        if (oper != "") {
            # Fix the address.
            src_code[inst_count, "1"] = \
                encode_branch(src_code[inst_count, "1"], \
                              src_code[inst_count, "2"], \
                              word_add(pgm_cntr, 1))
        }
    } else if (oper ~ /^\(.*\)[ \t]*,[ \t]*Y$/) {
        # Indirect zero page Indexed Y.
        mode = 12
        bytes = 1

        # Get the value of the operand.
        sub(/\)[ \t]*,[ \t]*Y$/, "", oper)
        if (eval_operand(substr(oper, 2, length(oper) - 1), inst_count, 0) == 2) {
            add_error("Operand larger than a byte")
        }
    } else if (oper ~ /^.*,[ \t]*[XY]$/) {
        # X or Y indexed.
        if (substr(oper, length(oper), 1) == "X") {
            mode = 7; # Absolute Indexed X.
        } else {
            mode = 8; # Absolute Indexed Y.
        }
        bytes = 2

        # Get the value of the operand.
        sub(/,[ \t]*[XY]$/, "", oper)
        if (eval_operand(oper, inst_count, 0) == 1) {
            # If there is a Zero Paged mode for this instruction use it.
            if (substr(inst_encode, code + ((mode + 2) * 2), 2) != "  ") {
                # The zero page versions are two larger.
                mode = mode + 2
                bytes = 1
            }
        }
    } else if (oper ~ /^\(.*,[ \t]*X[ \t]*\)$/) {
        # Indirect absolute Indexed X.
        mode = 6
        bytes = 2

        # Get the value of the operand.
        sub(/,[ \t]*X[ \t]*\)$/, "", oper)
        if (eval_operand(substr(oper, 2, length(oper) - 1), inst_count, 0) == 1) {
            # If there is a Zero Paged mode for this instruction use it.
            if (substr(inst_encode, code + (11 * 2), 2) != "  ") {
                # Indirect zero page.
                mode = 11
                bytes = 1
            }
        }
    } else if (oper ~ /^\(.*\)$/) {
        # Indirect absolute or zero page.
        mode = 5
        bytes = 2

        # Get the value of the operand.
        if (eval_operand(substr(oper, 2, length(oper) - 2), inst_count, 0) == 1) {
            # If there is a Zero Paged mode for this instruction use it.
            if (substr(inst_encode, code + (3 * 2), 2) != "  ") {
                # Indirect zero page.
                mode = 3
                bytes = 1
            }
        }
    } else {
        # Absolute or zero page.
        mode = 1; # Default to absolute.
        bytes = 2

        # Get the value of the operand.
        if (eval_operand(oper, inst_count, 0) == 1) {
            # If there is a Zero Paged mode for this instruction use it.
            if (substr(inst_encode, code + (2 * 2), 2) != "  ") {
                # Zero page.
                mode = 2
                bytes = 1
            }
        }
    }

    # Get the OP code. Checks the addressing mode too.
    code = substr(inst_encode, code + (mode * 2), 2)
    if (code == "  ") {
        add_error("Invalid addressing mode")
        return
    }

    # Save the OP code.
    src_code[inst_count, "C"] = code

    # Save the address.
    src_code[inst_count, "A"] = make_hex(2, pgm_cntr)

    # Save the number of bytes this instruction takes.
    src_code[inst_count, "B"] = bytes

    # Increment the PC for each byte of the instruction.
    pgm_cntr = word_add(pgm_cntr, bytes)
}

# encode_pseudo(line, label) - Encode a Pseudo instruction. {{{2
# Symbols used in the operand must be defined.
# line      - The line to encode.
# label     - The label for the line, if there is any.
# inst      - The pseudo instruction. (Private)
function encode_pseudo(line, label, inst) {
    if (match(line, /^\*[ \t]*=/)) {
        # Altering the Program Counter.
        line = substr(line, RLENGTH + 1, length(line) - RLENGTH)
        pgm_cntr = word_add(eval_expr(line, 1), 0)

        # If there was a label on this line set it to the new PC.
        if (label != "") {
            symbols[label] = pgm_cntr
        }
    } else if (match(line, /^[ \t]*=/)) {
        # Assigning a label a value.
        if (label != "") {
            line = substr(line, RLENGTH + 1, length(line) - RLENGTH)
            symbols[label] = eval_expr(line, 1)
        } else {
            add_error("Missing label with '='")
        }
    } else {
        # Get the pseudo instruction.
        match(line, /^\.[A-Z]*/)
        inst = substr(line, 1, RLENGTH)
        sub(/^\.[A-Z]*[ \t]*/, "", line)

        # Evaluate the pseudo instruction.
        if (inst ~ /^\.BY/) {
            # A single byte.
            src_code[inst_count, "B"] = 1

            # Get the value.
            eval_operand(line, inst_count, 0)

            # Make sure byte 2 is cleared.
            src_code[inst_count, "2"] = ""

            # Save the address.
            src_code[inst_count, "A"] = make_hex(2, pgm_cntr)

            # Mark this as data.
            data_loc[src_code[inst_count, "A"]] = 1

            # Increment the Program Counter.
            pgm_cntr = word_add(pgm_cntr, 1)
        } else if (inst  ~ /^\.ENDM/) {
            # End of a Macro.
            macros["_name"] = ""
            src_code[inst_count, "M"] = ""
        } else if (inst  ~ /^\.EQ/) {
            # Assign a symbol a value.
            if (label != "") {
                symbols[label] = eval_expr(line, 1)
            } else {
                add_error(sprintf("Missing label with '%s'", inst))
            }
        } else if (inst  ~ /^\.IN/) {
            # Include another file.
            load_file(line)
        } else if (inst  ~ /^\.MA/) {
            # Setup the Macro name and pointer.
            macros["_name"] = line

            # See if this macro has been defined before.
            if (macros["_name"] in macros) {
                add_error(sprintf("Macro already defined '%s'", macros["_name"]))
            }

            # Check the macro name to make sure it's valid.
            if (macros["_name"] !~ /^[A-Z][A-Z0-9_.]*$/) {
                # It's invalid. Emit an error then ignore it.
                add_error(sprintf("Invalid macro name '%s'", macros["_name"]))
            }

            # Set the pointer to where the macro starts.
            macros[macros["_name"]] = inst_count
        } else if (inst  ~ /^\.OR/) {
            # Altering the Program Counter.
            pgm_cntr = word_add(eval_expr(line, 1), 0)

            # If there was a label on this line set it to the new PC.
            if (label != "") {
                symbols[label] = pgm_cntr
            }
        } else if (inst  ~ /^\.ST/) {
            # A string of text.
            encode_string(line)
        } else if (inst ~ /^\.WO/ || inst ~ /^\.DB/) {
            # A word.
            src_code[inst_count, "B"] = 2

            # Get the value.
            line = eval_operand(line, inst_count, 0)

            # Special processing for .DBYTE
            if (inst ~ /^\.DB/) {
                if (line == "") {
                    # Unresolved symbol.
                    # Make sure the bytes are swapped later.
                    src_code[inst_count, "B"] = 4

                } else {
                    # Swap the bytes.
                    line = src_code[inst_count, "1"]
                    src_code[inst_count, "1"] = src_code[inst_count, "2"]
                    src_code[inst_count, "2"] = line
                }
            }

            # Save the address.
            src_code[inst_count, "A"] = make_hex(2, pgm_cntr)

            # Mark this as data.
            data_loc[src_code[inst_count, "A"]] = 2

            # Increment the Program Counter.
            pgm_cntr = word_add(pgm_cntr, 2)
        } else if (inst ~ /^\.LI/) {
            # Set listing options.
            if (length(line) == 0) {
                list_array["list"] =  1;
            } else {
                while (length(line) > 0) {
                    if (line ~ /^ON/)   { list_array["list"] =  1; } else 
                    if (line ~ /^OFF/)  { list_array["list"] =  0; } else 
                    if (line ~ /^PART/) { list_array["list"] = -1; } else 
                    if (line ~ /^DON/)  { list_array["data"] =  1; } else 
                    if (line ~ /^DOFF/) { list_array["data"] =  0; } else 
                    if (line ~ /^SON/)  { list_array["sym"] =   1; } else 
                    if (line ~ /^SOFF/) { list_array["sym"] =   0; }
                    sub(/[A-Z]*[, \t]*/, "", line)
                }
            }

            # Reset the option for the current line.
            src_code[inst_count, "L"] = list_array["list"]
        } else if (inst ~ /^\.NL/) {
            # Shorthand for" .LIST OFF".
            list_array["list"] =  0;

            # Reset the option for the current line.
            src_code[inst_count, "L"] = list_array["list"]
        } else {
            add_error(sprintf("Unkown pseudo instruction '%s'", inst))
        }
    }
}

# encode_string(string) - Encodes a string. {{{2
# string    - The string to encode.
# pos       - The position in the string. (Private)
# bytes     - the number of bytes in the string. (Private)
# start     - The start address of the string. (Private)
function encode_string(string, pos, bytes) {
    # Find the original string.
    pos = index(toupper(src_code[inst_count, "O"]), string)
    string = substr(src_code[inst_count, "O"], \
                    pos, \
                    length(src_code[inst_count, "O"]) - pos + 1)

    # Strip the leading quote.
    sub(/^"/, "", string)

    # Find the ending quote and remove it.
    pos = 1
    while (pos <= length(string)) {
        if (substr(string, pos, 1) == "\"") {
            if (pos == length(string)) {
                break
            } else {
                if (substr(string, pos + 1, 1) == "\"") {
                    pos++
                } else {
                    break
                }
            }
        }
        pos++
    }
    string = substr(string, 1, pos - 1)

    # Replace doubled double quotes with single double quotes.
    gsub(/""/, "\"", string)

    # Encode the string.
    pos = 1
    bytes = 0
    while (pos < length(string) + 1) {
        # Setup src_code unless this is the first pass.
        if (pos > 1) {
            init_source("")
        } else {
            start = make_hex(2, pgm_cntr)
        }

        # Get the character(s) from the end of the string.
        src_code[inst_count, "1"] = char_num(substr(string, pos, 1))
        src_code[inst_count, "B"] = 1
        if (pos != length(string)) {
            src_code[inst_count, "2"] = char_num(substr(string, pos + 1, 1))
            src_code[inst_count, "B"] = 2
        }

        # Save the address.
        src_code[inst_count, "A"] = make_hex(2, pgm_cntr)

        # Increment the Program Counter.
        pgm_cntr = word_add(pgm_cntr, src_code[inst_count, "B"])

        # Increment the position and bytes counters.
        pos = pos + src_code[inst_count, "B"]
        bytes = bytes + src_code[inst_count, "B"]
    }

    # Mark this as data.
    data_loc[start] = bytes
}

# encode_sweet16(inst, oper) - Attempt to encode a sweet16 instruction. {{{2
# inst      - The instruction.
# oper      - The operand.
# code      - The OP code/line in the encoding string. (Private)
# bytes     - Bytes used in addition to the instruction. (Private)
# indirect  - The instruction is indirect.
function encode_sweet16(inst, oper, code, bytes, indirect) {
    bytes = 0
    if (inst == "RTN") {
        code = 0
    } else if (inst == "BK") {
        code = 10
    } else if (inst == "RS") {
        code = 11
    } else if (inst ~ /^B/) {
        # Branching.
        if (inst == "BR")   { code =  1; } else 
        if (inst == "BNC")  { code =  2; } else 
        if (inst == "BC")   { code =  3; } else 
        if (inst == "BP")   { code =  4; } else 
        if (inst == "BM")   { code =  5; } else 
        if (inst == "BZ")   { code =  6; } else 
        if (inst == "BNZ")  { code =  7; } else 
        if (inst == "BM1")  { code =  8; } else 
        if (inst == "BNM1") { code =  9; } else 
        if (inst == "BS")   { code = 12; } else {
            add_error(sprintf("Unknown instruction '%s'", inst))
            return
        }
        bytes = 1

        # Mark it as using a relative address. This is so the address is
        # adjusted correctly if a symbol is not defined now.
        src_code[inst_count, "R"] = 1

        # Get the value of the operand.
        oper = eval_operand(oper, inst_count, 0)
        if (oper != "") {
            # Fix the address.
            src_code[inst_count, "1"] = \
                encode_branch(src_code[inst_count, "1"], \
                              src_code[inst_count, "2"], \
                              word_add(pgm_cntr, 1))
        }
    } else {
        # Register based instructions.

        # Determin if the instruction is indirect.
        indirect = sub(/^@/, "", oper)

        # Encode the instruction.
        if (inst == "SET") {
            # Setup the instruction
            code = 16
            bytes = 2

            # Get the value.
            match(oper, /,.*/)
            eval_operand(substr(oper, RSTART + 1, RLENGTH - 1), inst_count, 1)

            # Remove the value.
            sub(/[ \t]*,.*$/, "", oper)
        } else if (inst == "LD" && !indirect)   { code =  32
        } else if (inst == "LD" &&  indirect)   { code =  64
        } else if (inst == "ST" && !indirect)   { code =  48
        } else if (inst == "ST" &&  indirect)   { code =  80
        } else if (inst == "LDD")               { code =  96
        } else if (inst == "STD")               { code = 112
        } else if (inst == "POP")               { code = 128
        } else if (inst == "STP")               { code = 144
        } else if (inst == "ADD")               { code = 160
        } else if (inst == "SUB")               { code = 176
        } else if (inst == "POPD")              { code = 192
        } else if (inst == "CPR")               { code = 208
        } else if (inst == "INR")               { code = 224
        } else if (inst == "DCR")               { code = 240
        } else {
            add_error(sprintf("Unknown instruction '%s'", inst))
            return
        }
        code = code + eval_expr(oper, 1)
    }

    # Save the OP code.
    src_code[inst_count, "C"] = make_hex(1, code)

    # Save the address.
    src_code[inst_count, "A"] = make_hex(2, pgm_cntr)

    # Save the number of bytes this instruction takes.
    src_code[inst_count, "B"] = bytes

    # Increment the PC for each byte of the instruction.
    pgm_cntr = word_add(pgm_cntr, bytes)
}

# eval_operand(oper) - Evaluates an operand. {{{2
# Returns the number of bytes to operand consumed or "" for a missing symbol or
# if there was an error in the expression.
# oper      - The operand to evaluate.
# pos       - The position in the source.
# undef     - Generate an error when a symbol is not defined.
# value     - The result of the evaluation. (Private)
function eval_operand(oper, pos, undef, value) {
    # Fix local labels.
    gsub(/:/, last_label "_", oper)

    # Evaluate the operand.
    value = eval_expr(oper, undef)

    # Check and handle the operand.
    if (value == "") {
        # Error handled elsewhere or an undefined symbol.
        src_code[pos, "D"] = oper
        return ""
    } else if (value > 255) {
        # Two bytes.
        src_code[pos, "1"] = byte_low(value)
        src_code[pos, "2"] = byte_high(value)
        return 2
    } else {
        # One byte,
        src_code[pos, "1"] = byte_low(value)
        src_code[pos, "2"] = 0
        return 1
    }
}

# init_source(line) - Initializes a an entry in src_code. {{{2
# line      - The original line of source code.
function init_source(line) {
    # Save the original source information.
    ++inst_count
    src_code[inst_count, "F"] = file_name
    src_code[inst_count, "N"] = file_line
    src_code[inst_count, "O"] = line

    # Setup defaults for the instruction.
    src_code[inst_count, "1"] = ""
    src_code[inst_count, "2"] = ""
    src_code[inst_count, "A"] = ""
    src_code[inst_count, "B"] = 0
    src_code[inst_count, "C"] = ""
    src_code[inst_count, "D"] = ""
    src_code[inst_count, "L"] = list_array["list"]
    src_code[inst_count, "M"] = macros["_name"]
    src_code[inst_count, "R"] = 0
}

# load_file(file) - Loads a source file. {{{2
# file      - The file to load.
# line      - The current source line. (Private)
# num       - The current line number. (Private)
# sfile     - The current file name. (Private)
# sline     - The current file line. (Private)
# slist     - The current listing state. (Private)
function load_file(file, line, num, sfile, sline, slist) {
    # Save the current state.
    sfile = file_name
    sline = file_line
    slist = list_array["list"]

    # Find the file name in the original source line.
    # What was passed is all uppercase.
    file = substr(src_code[inst_count, "O"], \
                  index(toupper(src_code[inst_count, "O"]), file), \
                  length(file))

    # Make sure the file exists.
    num = getline line < file
    close(file)
    if (num <= 0) {
        # Error loading the file.
        # Try adding 'rom/' to the file name.
        num = getline line < ("rom/" file)
        close("rom/" file)
        if (num <= 0) {
            add_error(sprintf("Unable to load the file '%s'", file))
            return
        } else {
            file = "rom/" file
        }
    }

    # Load the file.
    file_name = file
    num = 0
    while ((getline line < file) > 0) {
        file_line = ++num
        load_source(line)
    }
    close(file)

    # Restore the state.
    file_name = sfile
    file_line = sline
    list_array["list"] = slist
}

# load_macro(line, label) - Loads a Macro. {{{2
# macro     - The macro name.
# line      - The parameters to the macro call.
# call      - The macro call #.
# pos       - Source position counter. (Private)
# parms     - The parameters passed to the macro. (Private)
# i         - Temporary counter. (Private)
# slast     - The previous value for last_label. (Private)
function load_macro(macro, line, call, pos, parms, i, slast) {
    # Get the call #.
    call = ++macros["_call"]

    # Save and replace last_label.
    slast = last_label
    last_label = macro "_" call

    # Initialize the parameters to 0.
    parms["count"] = 0
    for (i = 1; i <= 9; i++) {
        parms[i] = 0
    }

    # Get the parameters.
    while (length(line) > 0) {
        parms["count"]++
        i = index(line, ",")
        if (i == 0) {
            parms[parms["count"]] = line
            line = ""
        } else {
            parms[parms["count"]] = substr(line, 1, i - 1)
            line = substr(line, i + 1, length(line) - i)
            sub(/[ \t]*/, "", line)
        }
    }

    # Make sure the macro exists.
    if (!(macro in macros)) {
        add_error(sprintf("Undefined Macro '%s'", macro))
        return
    }

    # Load the macro source from src_code.
    pos = macros[macro] + 1
    while (src_code[pos, "M"] == macro) {
        # Get the line.
        line = src_code[pos, "O"]

        # Replace parameters.
        if (line ~ /][0-9]/) {
            for (i = 1; i <= 9; i++) {
                gsub("]" i, parms[i], line)
            }
        }
        gsub("]#", parms["count"], line)

        # Load the line.
        load_source(line)
        pos++
    }

    # Put last_label back to what it was.
    last_label = slast
}

# load_source(source) - Loads a line of source code. {{{2
# line      - The line of source to load.
# inst      - The instruction.
# label     - the label for the line.
function load_source(line, inst, label) {
    # Initialize the entry in src_code.
    init_source(line)

    # Uppercase the source to make processing simpler.
    line = toupper(line)

    # If loading a macro skip the rest.
    if (macros["_name"] != "" && line !~ /\.ENDM/) {
        return
    }

    # Strip out comments.
    sub(/[ \t]*;.*$/, "", line)

    # Skip this line if there is nothing left.
    if (length(line) == 0) {
        return
    }

    # Check for a label.
    if (match(line, /^[^ \t][^ \t]*/)) {
        # Get the label and remove it from the source line.
        label = substr(line, RSTART, RLENGTH)
        sub(/^[^ \t][^ \t]*[ \t]*/, "", line)

        # Check the label to make sure it's valid.
        if (label !~ /^[A-Z:][A-Z0-9_.]*$/) {
            # It's invalid. Emit an error then ignore it.
            add_error(sprintf("Invalid label '%s'", label))
            label = ""
        } else {
            # See if it is a local label.
            if (label ~ /^:/) {
                # Prefix it with the previous label.
                label = last_label "_" substr(label, 2, length(label) - 1)
            } else {
                # Save it for the next local label.
                last_label = label
            }

            # Set it in the symbol table.
            symbols[label] = pgm_cntr
            sym_count[label] = 0
        }
    } else {
        # No label, remove the leading white space.
        sub(/^[ \t]*/, "", line)
        label = ""
    }

    # Check for Pseudo operations.
    if (line ~ /^[.=*]/) {
        encode_pseudo(line, label)
        return
    }

    # Get the instruction.
    match(line, /^[^ \t]*/)
    inst = substr(line, RSTART, RLENGTH)
    sub(/^[^ \t]*[ \t]*/, "", line)

    # Check for a Macro call.
    if (inst in macros) {
        src_code[inst_count, "M"] = 0
        load_macro(inst, line)
        return
    }

    # Encode the instruction.
    encode_instr(inst, line)

    # Increment the Program Counter.
    pgm_cntr = word_add(pgm_cntr, 1)
}

# second_pass() - Passs over the assembled source a second time. {{{2
# Any symbols that were undefined the first time should be defined now.
# pos       - Position counter. (Private)
# temp      - Temporary variable. (Private)
function second_pass(pos) {
    # check each line of source code.
    for (pos = 1; pos <= inst_count; pos++) {
        if (src_code[pos, "D"] != "") {
            # Set the file name and line number for errors.
            file_name = src_code[pos, "F"]
            file_line = src_code[pos, "N"]

            # Attempt to re-evaluate the operand.
            eval_operand(src_code[pos, "D"], pos, 1)

            # fix the operand if it uses a relative address.
            if (src_code[pos, "R"] == 1) {
                src_code[pos, "1"] = \
                    encode_branch(src_code[pos, "1"], \
                                  src_code[pos, "2"], \
                                  convert_base(16, 10, src_code[pos, "A"]) + 1)
            }

            # Check for special processing.
            if (src_code[pos, "B"] == 1) {
                # If it is only supposed to have a single byte make sure the
                # second is cleared.
                src_code[pos, "2"] = ""
            } else if (src_code[pos, "B"] == 4) {
                # The bytes need to be swapped.
                src_code[pos, "B"] = 2
                temp = src_code[pos, "1"]
                src_code[pos, "1"] = src_code[pos, "2"]
                src_code[pos, "2"] = temp
            }
        }
    }
}

# Byte and word manipulation. {{{1

# byte_and(bytea, byteb) - Performs a bitwise AND of two bytes. {{{2
# bytea     - The first byte.
# byteb     - The second byte.
# byte      - The new byte. (Private)
# i         - Byte counter. (Private)
function byte_and(bytea, byteb, byte, i){
    # Convert the bytes to binary strings.
    bytea = sprintf("%08s", convert_base(10, 2, bytea))
    byteb = sprintf("%08s", convert_base(10, 2, byteb))

    # Perform the XOR.
    byte = ""
    for (i = 1; i <= 8; i++) {
        if (substr(bytea, i, 1) == 1 && substr(byteb, i, 1) == 1) {
            byte = byte 1
        } else {
            byte = byte 0
        }
    }

    # Return the new byte, base 10.
    return convert_base(2, 10, byte)
}

# byte_high(word) - Returns the high byte from the word. {{{2
# word      - The word to get the high byte from.
function byte_high(word) {
    while (word >= 65536) {
        word = word - 65536
    }
    return int(word / 256)
}

# byte_low(word) - Returns the low byte from the word. {{{2
# word      - The word to get the low byte from.
function byte_low(word) {
    return (word % 256)
}

# byte_not(bytea, byteb) - Performs a bitwise NOT of a byte. {{{2
# byte      - The byte to not.
# new       - The new byte. (Private)
# i         - Byte counter. (Private)
function byte_not(byte, new, i){
    # Convert the byte to a binary string.
    byte = sprintf("%08s", convert_base(10, 2, byte))

    # Perform the NOT.
    new = ""
    for (i = 1; i <= 8; i++) {
        if (substr(byte, i, 1) == 1) {
            new = new 0
        } else {
            new = new 1
        }
    }

    # Return the byte, base 10.
    return convert_base(2, 10, new)
}

# byte_or(bytea, byteb) - Performs a bitwise OR of two bytes. {{{2
# bytea     - The first byte.
# byteb     - The second byte.
# byte      - The new byte. (Private)
# i         - Byte counter. (Private)
function byte_or(bytea, byteb, byte, i){
    # Convert the bytes to binary strings.
    bytea = sprintf("%08s", convert_base(10, 2, bytea))
    byteb = sprintf("%08s", convert_base(10, 2, byteb))

    # Perform the XOR.
    byte = ""
    for (i = 1; i <= 8; i++) {
        if (substr(bytea, i, 1) == 1 || substr(byteb, i, 1) == 1) {
            byte = byte 1
        } else {
            byte = byte 0
        }
    }

    # Return the new byte, base 10.
    return convert_base(2, 10, byte)
}

# byte_xor(bytea, byteb) - Performs a bitwise XOR of two bytes. {{{2
# bytea     - The first byte.
# byteb     - The second byte.
# bita      - Test bit from bytea.
# bitb      - Test bit from byteb.
# byte      - The new byte. (Private)
# i         - Byte counter. (Private)
function byte_xor(bytea, byteb, bita, bitb, byte, i){
    # Convert the bytes to binary strings.
    bytea = sprintf("%08s", convert_base(10, 2, bytea))
    byteb = sprintf("%08s", convert_base(10, 2, byteb))

    # Perform the XOR.
    byte = ""
    for (i = 1; i <= 8; i++) {
        bita = substr(bytea, i, 1)
        bitb = substr(byteb, i, 1)
        if ((bita == 1 && bitb == 0) || (bita == 0 && bitb == 1)) {
            byte = byte 1
        } else {
            byte = byte 0
        }
    }

    # Return the new byte, base 10.
    return convert_base(2, 10, byte)
}

# word_add(worda, wordb) - Adds two words together. {{{2
# worda     - The first word.
# wordb     - The second word.
# word      - The new word. (Private)
function word_add(worda, wordb, word) {
    # Add the words.
    word = worda + wordb

    # Make sure the result is not larger than a word.
    while (word >= 65536) {
        word = word - 65536
    }

    # Return the new word,
    return word
}

# Expression Evaluation: {{{1

# char_num(char) - Convert a character to it's ASCII value. {{{2
# If the character is not recognized it is treated as a null.
# char      - The character to convert.
# num       - The ASCII number for the character. (Private)
function char_num(char, num) {
    # Find the character in the lookup string.
    num = index(ascii_str, char)
    if (num > 0) {
        num = num + 31
    }

    # Return the number.
    return num
}

# eval_expr(expr) - Evaluate an expression and return it's value. {{{2
# Calls its self recursively to evaluate expressions.
# expr      - The expression to evaluate.
# undef     - Generate an error when a symbol is not defined.
# left      - The left side of the expression. (Private)
# op        - The expression operation. (Private)
# right     - The right site of the expression. (Private)
function eval_expr(expr, undef, left, op, right) {
    # Defaults.
    op = ""
    right = ""

    # Strip leading and trailing white space.
    sub(/^[ \t]*/, "", expr)
    sub(/[ \t]*$/, "", expr)

    # Check for a prefix operand.
    if (expr ~ /^[~<>]/) {
        # Store it in op temporarily.
        op = substr(expr, 1, 1)
        expr = substr(expr, 2, length(expr) - 1)
    }

    # Get the left side of the expression.
    if (substr(expr, 1, 1) == "*") {
        # The Program Counter.
        left = pgm_cntr
        expr = substr(expr, 2, length(expr) - 1)
    } else if (match(expr, /^[A-Z][A-Z0-9_.]*/)) {
        # Symbol.
        left = substr(expr, 1, RLENGTH)
        sub(/^[A-Z][A-Z0-9_.]*/, "", expr)
        if (left in symbols) {
            # Get the value from the symbol table.
            sym_count[left]++
            left = symbols[left]
        } else {
            # Undefined symbol.
            if (undef == 1) {
                add_error(sprintf("Undefined symbol '%s'", left))
            }
            return ""
        }
    } else if (match(expr, /^[@$%0-9][0-9A-F]*/)) {
        # Number.
        left = convert_number(substr(expr, 1, RLENGTH))
        sub(/^[@$%0-9][0-9A-F]*/, "", expr)
    } else if (substr(expr, 1, 1) == "'") {
        # Character.
        left = char_num(substr(expr, 2, 1))
        sub(/^'./, "", expr)
    } else if (substr(expr, 1, 1) == "[") {
        # Grouped expression.
        # Use right to point to where the group ends.
        right = find_group(expr)

        # Make sure the closing bracket was found.
        if (right == 0) {
            add_error("Missing closing bracket ']'")
            return ""
        }

        # Evaluate the grouped expression.
        left = eval_expr(substr(expr, 2, right - 2), undef)
        if (left == "") {
            # There must have been an error.
            return ""
        }

        # Remove the group from the expression and continue.
        if (right == length(expr)) {
            expr = ""
        } else {
            expr = substr(expr, right + 1, length(expr) - right)
        }

        # Reset right to an empty string.
        right = ""
    } else {
        # Catchall.
        left = expr
        expr = ""
    }

    # Strip leading white space.
    sub(/^[ \t]*/, "", expr)

    # If there is a prefix operand evaluate it.
    if (op != "") {
        left = eval_prefix(left, op)
        op = ""
    }

    # If there is nothing left return the left site.
    if (length(expr) == 0) {
        return left
    }

    # Get the operand.
    if (expr ~ /[+*%^\/&|-]/) {
        op = substr(expr, 1, 1)
        expr = substr(expr, 2, length(expr) - 1)
    } else {
        add_error(sprintf("Uknown operand '%s'", substr(expr, 1, 1)))
        return ""
    }

    # Get the right side.
    if (length(expr) > 0) {
        right = eval_expr(expr, undef)
        if (right == "") {
            # There was an error along the way.
            return ""
        }
    } else {
        # There is no right side and one was expected.
        add_error("Incomplete expression")
        return ""
    }

    # Evaluate the expression.
    return eval_infix(left, op, right)
}

# eval_infix(left, op, right) - Evaluates an infix expression. {{{2
# left      - The left side of the expression.
# op        - The operation to perform.
# right     - The right side of the expression.
function eval_infix(left, op, right) {
    if (op == "+") { return left + right;          } else
    if (op == "-") { return left - right;          } else
    if (op == "/") { return int(left / right);     } else
    if (op == "*") { return left * right;          } else
    if (op == "%") { return left % right;          } else
    if (op == "^") { return byte_xor(left, right); } else
    if (op == "&") { return byte_and(left, right); } else
    if (op == "|") { return byte_or(left, right);  }

    # Just in case the impossible happens and this is reached.
    add_error(sprintf("Unknown operation '%s'", op))
    return ""
}

# eval_prefix(left, op) - Evaluates a prefix expression. {{{2
# left      - The left side of the expression.
# op        - The operation to perform.
function eval_prefix(left, op) {
    if (op == "~") { return byte_not(left);  } else
    if (op == "<") { return byte_low(left);  } else
    if (op == ">") { return byte_high(left); }

    # Just in case the impossible happens and this is reached.
    add_error(sprintf("Unknown operation '%s'", op))
    return ""
}

# find_group(expr) - Finds the closing bracket in a group. {{{2
# Returns the position of the matching bracket or 0 if it is not found.
# expr      - The expression to find the closing bracket in.
# found     - The number of brackets found. (Private)
# i         - String position counter. (Private)
function find_group(expr, found, i) {
    # Count the initial bracket.
    found = 1

    # Start after the first bracket.
    for (i = 2; i <= length(expr); i++) {
        if (substr(expr, i, 1) == "[") {
            found++
        } else if (substr(expr, i, 1) == "]") {
            found--
        }
        if (found == 0) {
            return i
        }
    }

    # The closing bracket was not found.
    return 0
}

# Utilities. {{{1

# add_error(error) - Add an error message to the error list. {{{2
# error     - The error text to add.
function add_error(error) {
    errors[++errors["_count"]] = \
        sprintf("; ** %s on line # %s of file '%s'.", \
                error, file_line, file_name)
}

# convert_base(from, to, number) - Convert the base of a number. {{{2
# Works by converting the number to base 10 then to the desired base.
# from      - The base the number is currently in.
# to        - The base to convert the number to.
# number    - The number to convert.
# new       - Temporary number used for conversions. (Private)
# i         - Counter. (Private)
function convert_base(from, to, number, new, i) {
    # If the bases are the same just return the number.
    if (from == to) {
        return number + 0; # Add 0 to make sure it is a number.
    }

    # Convert the number to base 10 if it is not already.
    if (from != 10) {
        # Make sure the number is upper case if might contain letters.
        if (from > 10) {
            number = toupper(number)
        }

        # Perform the actual conversion.
        new = 0
        for(i = 1; i < length(number) + 1; i++){
            new = (new * from) + index(convert_str, substr(number, i, 1)) - 1
        }
        number = new
    }

    # Convert the number from base 10 to the desired base.
    if (to != 10 ) {
        new = ""
        while(number > 0){
            new = substr(convert_str, (number % to) + 1,1 ) new
            number = int(number / to)
        }
        number = new
    }

    # Return the number.
    return number
}

# convert_number(number) - Converts a number to base 10. {{{2
# The base of the nunmber is identified and converted.
# number    - The number to convert.
# char      - the first character of the number. (Private)
# base      - The base the number is currently in. (Private)
function convert_number(number, char, base) {
    # Check for just a 0.
    if (number == "0") {
        return 0
    }

    # Get the first character. It identifies the base.
    char = substr(number, 1, 1)

    # Identify the base.
    if (char == "%") {
        base = 2
    } else if (char == "@" || char == "0") {
        base = 8
    } else if (char == "$") {
        base = 16
    } else {
        # The number is base 10 already.
        # Just return it after making sure it's a number.
        return (number + 0)
    }

    # Convert and return it.
    return convert_base(base, 10, substr(number, 2, length(number) - 1))
}

# make_hex(bytes, value) - Turns value into a 0 prefixed hex string. {{{2
function make_hex(bytes, value) {
    if (bytes == 1) {
        return sprintf("%02s", convert_base(10, 16, value))
    } else if (bytes == 2) {
        return sprintf("%04s", convert_base(10, 16, value))
    }
}

# word_make(low, high) - Combines the high and low bytes into a word. {{{2
# low       - The low byte.
# high      - The high byte.
function word_make(low, high) {
    return (high * 256) + low
}

# print_assembled() - Print the assembled source. {{{2
# pos       - Position counter. (Private)
# prev      - The previous file name. (Private)
# type      - the type of line. (Private)
function print_assembled(pos, prev, type) {
    # No files yet.
    prev = ""

    # Print each line of source code.
    for (pos = 1; pos <= inst_count; pos++) {
        # If the file name changed print a notice.
        if (prev != src_code[pos, "F"] && src_code[pos, "L"] == 1) {
            if (prev != "") {
                # Blank line if not the first file.
                print ""
            }
            printf ";Adr OP B1 B2 ; Line Source File: %s\n", src_code[pos, "F"]
        }
        prev = src_code[pos, "F"]

        # Skip lines with no compiled code.
        if (src_code[pos, "A"] == "" && src_code[pos, "L"] != 1) {
            continue
        }

        # Address.
        printf "%4s ", src_code[pos, "A"]

        # OP Code.
        printf "%2s ", src_code[pos, "C"]

        # First byte.
        if (src_code[pos, "B"] >= 1) {
            printf "%02s ", convert_base(10, 16, src_code[pos, "1"])
        } else {
            printf "   "
        }

        # Second byte.
        if (src_code[pos, "B"] == 2) {
            printf "%02s ", convert_base(10, 16, src_code[pos, "2"])
        } else {
            printf "   "
        }

        # Determine the type.
        type = " "
        if (src_code[pos, "M"] == 0) {
            type = "M"
        } else if (src_code[pos, "M"] != "") {
            type = "m"
        } else if (src_code[pos, "C"] == "" && src_code[pos, "B"] != 0) {
            type = "d"
        } else if (src_code[pos, "C"] != "") {
            type = "c"
        }

        # The original source.
        if (src_code[pos, "L"] == 0) {
            print ""
        } else {
            printf ";%s%4s %s\n", type, src_code[pos, "N"], src_code[pos, "O"]
        }
    }
}

# print_data() - Prints the data addresses. {{{2
# addr      - The address currently being printed.
function print_data(addr) {
    print "; Data Locations:"
    for (addr in data_loc) {
        printf ";! %04s %d\n", addr, data_loc[addr]
    }
}

# print_errors() - Print the errors encountered. {{{2
# error     - The error currently being printed. (Private)
function print_errors(error) {
    for (error = 1; error <= errors["_count"]; error++) {
        print errors[error]
    }
}

# print_symbols() - Prints the symbol table. {{{2
# Only symbols that are actually used are printed.
# sym       - The symbol currently being printed.
function print_symbols(sym) {
    print "; Symbol Table:"
    for (sym in symbols) {
        if (sym_count[sym] > 0) {
            printf ";@ %-10s = %04s\n", sym, convert_base(10, 16, symbols[sym])
        }
    }
}

